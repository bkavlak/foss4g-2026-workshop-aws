"""The authenticator that runs inside the hub image.

The hub has no access to this project's Python package, so the verification
half of the credential policy is duplicated in the file the chart mounts. These
tests mint with `workshop.credentials` and check with that file, which is what
stops the two copies drifting apart.
"""

# A pytest fixture is referenced by a parameter of the same name, which Pylint
# reads as shadowing, and a fixture requested purely for its side effect looks
# unused. Both are the idiom, not a defect.
# pylint: disable=redefined-outer-name,unused-argument

import asyncio
import csv
import json

import pytest

from workshop import credentials
from workshop.roster import ROSTER_FILE, Roster


@pytest.fixture
def roster_on_disk(tmp_path):
    Roster.provision(tmp_path, count=3)
    payload = json.loads((tmp_path / ROSTER_FILE).read_text(encoding="utf-8"))
    return tmp_path / ROSTER_FILE, payload["participants"]


def test_hub_side_verification_accepts_this_project_s_credentials(
    authenticator,
):
    """Guards against the two scrypt policies diverging."""
    credential = credentials.mint()
    assert authenticator.verify(credential.verifier, credential.password)
    assert not authenticator.verify(
        credential.verifier, credential.password.swapcase()
    )


def test_resolve_returns_the_username_on_success(authenticator, tmp_path):
    Roster.provision(tmp_path, count=1)
    row = next(
        csv.DictReader((tmp_path / "handout.csv").open(encoding="utf-8"))
    )
    roster = json.loads((tmp_path / ROSTER_FILE).read_text(encoding="utf-8"))[
        "participants"
    ]
    assert (
        authenticator.resolve(roster, row["username"], row["password"])
        == row["username"]
    )


def test_resolve_is_forgiving_about_typing_but_not_about_passwords(
    authenticator, tmp_path
):
    Roster.provision(tmp_path, count=1)
    row = next(
        csv.DictReader((tmp_path / "handout.csv").open(encoding="utf-8"))
    )
    roster = json.loads((tmp_path / ROSTER_FILE).read_text(encoding="utf-8"))[
        "participants"
    ]

    assert authenticator.resolve(
        roster, f"  {row['username'].upper()} ", row["password"]
    )
    assert (
        authenticator.resolve(roster, row["username"], row["password"].upper())
        is None
    )


def test_unknown_user_and_malformed_input_are_refused(
    authenticator, roster_on_disk
):
    _, roster = roster_on_disk
    assert authenticator.resolve(roster, "instructor", "letmein") is None
    assert authenticator.resolve(roster, None, "letmein") is None
    assert authenticator.resolve(roster, "user1", None) is None
    assert authenticator.resolve({}, "user1", "anything") is None


def test_roster_is_reread_so_a_latecomer_can_be_added_without_a_restart(
    authenticator, tmp_path, monkeypatch
):
    Roster.provision(tmp_path, count=1)
    path = tmp_path / ROSTER_FILE
    monkeypatch.setenv("WORKSHOP_ROSTER_PATH", str(path))

    before = authenticator.load_roster(path)
    Roster.provision(tmp_path, count=2)
    after = authenticator.load_roster(path)

    assert set(before) == {"user1"}
    assert set(after) == {"user1", "user2"}

    row = next(
        csv.DictReader((tmp_path / "handout.csv").open(encoding="utf-8"))
    )
    assert authenticator.resolve(after, row["username"], row["password"])


def test_missing_roster_denies_login_rather_than_crashing_the_hub(
    authenticator, tmp_path, monkeypatch
):
    """A hub that raises on login is harder to diagnose than one that denies."""
    monkeypatch.setenv("WORKSHOP_ROSTER_PATH", str(tmp_path / "absent.json"))
    auth = authenticator.RosterAuthenticator()
    result = asyncio.run(
        auth.authenticate(None, {"username": "user1", "password": "x"})
    )
    assert result is None


@pytest.mark.parametrize(
    "typed", ["user1", "USER1", " user1 ", "\tUser1\n", "uSeR1"]
)
def test_both_sides_agree_on_what_counts_as_the_same_username(
    authenticator, tmp_path, typed
):
    """Local check and hub must answer identically, or the runbook lies."""
    Roster.provision(tmp_path, count=1)
    row = next(
        csv.DictReader((tmp_path / "handout.csv").open(encoding="utf-8"))
    )
    roster_file = json.loads(
        (tmp_path / ROSTER_FILE).read_text(encoding="utf-8")
    )["participants"]
    roster = Roster.load(tmp_path)

    hub_says = (
        authenticator.resolve(roster_file, typed, row["password"]) is not None
    )
    local_says = roster.authenticates(typed, row["password"])
    assert hub_says is True
    assert local_says is True


def test_neither_side_is_lenient_about_passwords(authenticator, tmp_path):
    Roster.provision(tmp_path, count=1)
    row = next(
        csv.DictReader((tmp_path / "handout.csv").open(encoding="utf-8"))
    )
    roster_file = json.loads(
        (tmp_path / ROSTER_FILE).read_text(encoding="utf-8")
    )["participants"]
    roster = Roster.load(tmp_path)

    sloppy = f" {row['password']} "
    assert authenticator.resolve(roster_file, row["username"], sloppy) is None
    assert roster.authenticates(row["username"], sloppy) is False
