"""The set of participants for one workshop, and their login credentials.

A roster exists in exactly one state: usernames paired with verifiers.
Plaintext passwords are deliberately *not* reachable through this type.  They
exist for the duration of :meth:`Roster.provision`, which writes them straight
to the handout file, and nowhere else.  There is therefore no such thing as a
half-populated roster that a caller has to interrogate before trusting.

Two files make up a provisioned roster directory:

``roster.json``   usernames and verifiers; read by OpenTofu, shipped to the
                  cluster as a Secret.  Safe to lose (re-provision) but not
                  safe to publish.
``handout.csv``   usernames and plaintext passwords, written 0600, for the
                  maintainer to print or paste into name cards.  Cannot be
                  regenerated from ``roster.json``.
"""

from __future__ import annotations

import csv
import json
import os
from collections.abc import Mapping
from pathlib import Path

from workshop import credentials
from workshop.credentials import Verifier

ROSTER_FILE = "roster.json"
HANDOUT_FILE = "handout.csv"

_HANDOUT_MODE = 0o600


def normalize_username(username: object) -> str:
    """Reduce a typed username to the form the roster stores.

    Participants read their username off a printed handout, so leading spaces
    and stray capitals are typing noise rather than a different person. The
    hub applies the same rule in
    ``charts/workshop/files/roster_authenticator.py``; the two are kept in step
    by a test rather than by convention.
    """
    return username.strip().lower() if isinstance(username, str) else ""


class Roster:
    """Usernames and the verifiers the hub needs to authenticate them."""

    def __init__(self, verifiers: Mapping[str, Verifier]) -> None:
        self._verifiers = dict(verifiers)

    @classmethod
    def provision(
        cls, directory: str | Path, count: int, prefix: str = "user"
    ) -> Roster:
        """Mint ``count`` accounts and write both files into ``directory``.

        Overwrites any roster already there: re-provisioning invalidates every
        previously handed-out password, which is the intended way to recover
        from a leaked handout.
        """
        if count < 1:
            raise ValueError("a workshop needs at least one participant")

        directory = Path(directory)
        directory.mkdir(parents=True, exist_ok=True)

        width = len(str(count))
        minted = {
            f"{prefix}{i:0{width}d}": credentials.mint()
            for i in range(1, count + 1)
        }

        _write_handout(directory / HANDOUT_FILE, minted)
        roster = cls({name: c.verifier for name, c in minted.items()})
        (directory / ROSTER_FILE).write_text(
            roster.document(), encoding="utf-8"
        )
        return roster

    @classmethod
    def load(cls, directory: str | Path) -> Roster:
        """Read a roster previously written by :meth:`provision`."""
        path = Path(directory) / ROSTER_FILE
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except FileNotFoundError as exc:
            raise FileNotFoundError(
                f"no roster at {path}; run `workshop provision` first"
            ) from exc
        return cls(payload["participants"])

    @property
    def usernames(self) -> list[str]:
        """The participant accounts, in a stable order."""
        return sorted(self._verifiers)

    def document(self) -> str:
        """The exact bytes that belong in the cluster Secret."""
        return (
            json.dumps(
                {"participants": self._verifiers}, indent=2, sort_keys=True
            )
            + "\n"
        )

    def authenticates(self, username: str, password: str) -> bool:
        """Whether these credentials belong to a participant of this workshop.

        Matches usernames exactly as the hub does, so that checking a
        participant's credentials here answers the question they are actually
        asking: "will this let me in?"
        """
        verifier = self._verifiers.get(normalize_username(username))
        return verifier is not None and credentials.verify(verifier, password)

    def __len__(self) -> int:
        """The number of participants this roster can admit."""
        return len(self._verifiers)


def _write_handout(
    path: Path, minted: dict[str, credentials.Credential]
) -> None:
    # Created 0600 before anything is written, so the plaintext is never
    # briefly world-readable on a shared machine.
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, _HANDOUT_MODE)
    with os.fdopen(fd, "w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["username", "password"])
        for name, credential in minted.items():
            writer.writerow([name, credential.password])
