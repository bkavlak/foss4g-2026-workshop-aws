"""Password material for workshop participants.

This module owns the entire credential policy: how strong a generated password
is, which alphabet it uses, which key-derivation function protects it, and how
the stored form is encoded.  Callers mint a credential and later check a
password; they never see a salt, a cost parameter or an encoding.

The derivation parameters travel *inside* each verifier rather than living as a
constant on the checking side.  That is what lets the hub keep authenticating
rosters minted by an older version of this tool after the policy is tightened.

Only ``hashlib`` and ``secrets`` are used, so the verification half of this
policy can be re-implemented in the JupyterHub image without adding a
dependency to it (see ``charts/workshop/files/roster_authenticator.py``).
"""

from __future__ import annotations

import hashlib
import hmac
import secrets
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any

# What the server stores for one participant: an opaque record that `verify`
# understands and that nothing else needs to look inside.
Verifier = Mapping[str, Any]

# Ambiguous glyphs are excluded: participants read these off a printed handout
# and mistyping 'l' for '1' costs workshop time.
_ALPHABET = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
_PASSWORD_LENGTH = 12

# scrypt cost. n=2**14 keeps a hub login well under 100 ms while making an
# offline attack on a leaked roster expensive. maxmem is stated explicitly so
# the cost can be raised later without tripping OpenSSL's default ceiling.
_KDF = {"n": 2**14, "r": 8, "p": 1}
_DKLEN = 32
_SALT_BYTES = 16
MAX_MEMORY = 128 * 1024 * 1024


@dataclass(frozen=True)
class Credential:
    """A freshly minted credential, in both of the forms it is needed in.

    ``password`` is the plaintext that goes on the participant handout and is
    never persisted anywhere else.  ``verifier`` is the only half that may be
    shipped to the cluster.
    """

    password: str
    verifier: dict[str, Any]


def mint() -> Credential:
    """Generate a new password and the verifier that proves knowledge of it."""
    password = "".join(
        secrets.choice(_ALPHABET) for _ in range(_PASSWORD_LENGTH)
    )
    salt = secrets.token_bytes(_SALT_BYTES)
    digest = _derive(password, salt, _KDF, _DKLEN)
    verifier = {"salt": salt.hex(), "hash": digest.hex(), **_KDF}
    return Credential(password=password, verifier=verifier)


def verify(verifier: Verifier, password: str) -> bool:
    """Report whether ``password`` is the one ``verifier`` was minted from.

    A malformed or truncated verifier is a failed login, not an exception:
    every caller is an authentication path, and there is nothing useful for one
    to do with the distinction.
    """
    try:
        salt = bytes.fromhex(verifier["salt"])
        expected = bytes.fromhex(verifier["hash"])
        cost = {
            "n": int(verifier["n"]),
            "r": int(verifier["r"]),
            "p": int(verifier["p"]),
        }
        candidate = _derive(password, salt, cost, len(expected))
    except KeyError, TypeError, ValueError:
        return False
    return hmac.compare_digest(candidate, expected)


def _derive(
    password: str, salt: bytes, cost: Mapping[str, int], dklen: int
) -> bytes:
    return hashlib.scrypt(
        password.encode("utf-8"),
        salt=salt,
        n=cost["n"],
        r=cost["r"],
        p=cost["p"],
        dklen=dklen,
        maxmem=MAX_MEMORY,
    )
