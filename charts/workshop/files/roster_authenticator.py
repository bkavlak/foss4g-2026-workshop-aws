"""JupyterHub authenticator backed by the static workshop roster.

Runs inside the hub image, which we do not control, so it uses nothing beyond
the standard library and JupyterHub itself.

The roster is mounted read-only from a Secret and re-read on every login, so a
maintainer can add a latecomer by patching the Secret without restarting the
hub. It is small enough (one scrypt verifier per participant) that reading it
per login is cheaper than reasoning about cache invalidation.

The scrypt policy here is the verification half of ``workshop.credentials``;
``tests/test_roster_authenticator.py`` mints with that module and checks with
this file, so the two cannot drift apart unnoticed.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import os
from collections.abc import Mapping
from typing import Any

from jupyterhub.auth import Authenticator

Verifier = Mapping[str, Any]
Roster = Mapping[str, Verifier]

DEFAULT_ROSTER_PATH = "/etc/workshop/roster.json"
MAX_MEMORY = 128 * 1024 * 1024


def verify(verifier: Verifier, password: str) -> bool:
    """Whether ``password`` matches a ``workshop.credentials`` verifier."""
    try:
        salt = bytes.fromhex(verifier["salt"])
        expected = bytes.fromhex(verifier["hash"])
        candidate = hashlib.scrypt(
            password.encode("utf-8"),
            salt=salt,
            n=int(verifier["n"]),
            r=int(verifier["r"]),
            p=int(verifier["p"]),
            dklen=len(expected),
            maxmem=MAX_MEMORY,
        )
    except (KeyError, TypeError, ValueError):
        return False
    return hmac.compare_digest(candidate, expected)


def normalize_username(username: object) -> str:
    """Reduce a typed username to the form the roster stores.

    Mirrors ``workshop.roster.normalize_username``. Kept in step by
    ``tests/test_roster_authenticator.py`` rather than by convention.
    """
    return username.strip().lower() if isinstance(username, str) else ""


def resolve(roster: Roster, username: object, password: object) -> str | None:
    """Return the participant's username, or None if the credentials are wrong.

    Returning the roster's spelling of the name rather than what was typed
    keeps pod naming stable when someone types their username capitalised.
    """
    if not isinstance(password, str):
        return None
    name = normalize_username(username)
    verifier = roster.get(name)
    if verifier is None:
        return None
    return name if verify(verifier, password) else None


def load_roster(path: str | os.PathLike[str] | None = None) -> Roster:
    """Read the mounted roster.

    The location is resolved on every call rather than at import time so that
    the file the hub reads is always the one its pod spec points at.
    """
    path = path or os.environ.get("WORKSHOP_ROSTER_PATH", DEFAULT_ROSTER_PATH)
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)["participants"]


class RosterAuthenticator(Authenticator):
    """Authenticates the fixed set of accounts minted for this workshop."""

    # JupyterHub 5 separated authentication from authorisation and denies by
    # default: without this, every participant would supply a correct password,
    # be authenticated, and then be refused. The roster *is* the allowlist —
    # authenticate() returns a username only for someone on it — so everyone who
    # gets that far is authorised by construction.
    allow_all = True

    # handler is unused, but the signature is JupyterHub's, not ours.
    # pylint: disable=unused-argument
    async def authenticate(
        self, handler: object, data: Mapping[str, Any]
    ) -> str | None:
        """Check submitted credentials against the mounted roster.

        Args:
            handler: The Tornado handler for the login request. Unused.
            data: The submitted login form, with username and password keys.

        Returns:
            The participant's username, or None to refuse the login.
        """
        try:
            roster = load_roster()
        except (OSError, ValueError, KeyError):
            self.log.exception("workshop roster is missing or unreadable")
            return None
        return resolve(
            roster, data.get("username", ""), data.get("password", "")
        )
