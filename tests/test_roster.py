"""Provisioning a workshop's accounts."""

import csv
import json
import stat

import pytest

from workshop.roster import HANDOUT_FILE, ROSTER_FILE, Roster


def test_provision_creates_the_requested_number_of_accounts(tmp_path):
    roster = Roster.provision(tmp_path, count=5)
    assert len(roster) == 5
    assert len(set(roster.usernames)) == 5


def test_usernames_are_zero_padded_so_they_sort_and_read_consistently(tmp_path):
    roster = Roster.provision(tmp_path, count=12)
    assert roster.usernames[0] == "user01"
    assert roster.usernames[-1] == "user12"


def test_handout_passwords_authenticate_against_the_roster(tmp_path):
    """The promise: the paper a participant is handed lets them in."""
    roster = Roster.provision(tmp_path, count=4)
    with open(tmp_path / HANDOUT_FILE, newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            assert roster.authenticates(row["username"], row["password"])
            assert not roster.authenticates(row["username"], "hunter2")


def test_a_participant_cannot_log_in_as_another(tmp_path):
    roster = Roster.provision(tmp_path, count=3)
    rows = list(
        csv.DictReader((tmp_path / HANDOUT_FILE).open(encoding="utf-8"))
    )
    assert not roster.authenticates(rows[0]["username"], rows[1]["password"])


def test_unknown_user_is_rejected(tmp_path):
    roster = Roster.provision(tmp_path, count=2)
    assert not roster.authenticates("instructor", "anything")


def test_handout_is_not_readable_by_other_users(tmp_path):
    Roster.provision(tmp_path, count=1)
    mode = stat.S_IMODE((tmp_path / HANDOUT_FILE).stat().st_mode)
    assert mode & (stat.S_IRWXG | stat.S_IRWXO) == 0


def test_no_plaintext_password_reaches_the_cluster_document(tmp_path):
    Roster.provision(tmp_path, count=6)
    document = (tmp_path / ROSTER_FILE).read_text(encoding="utf-8")
    rows = list(
        csv.DictReader((tmp_path / HANDOUT_FILE).open(encoding="utf-8"))
    )
    for row in rows:
        assert row["password"] not in document


def test_cluster_document_is_the_shape_opentofu_reads(tmp_path):
    """infra/main.tf depends on this exact shape to read the roster."""
    Roster.provision(tmp_path, count=2)
    payload = json.loads((tmp_path / ROSTER_FILE).read_text(encoding="utf-8"))
    assert set(payload) == {"participants"}
    assert set(payload["participants"]) == {"user1", "user2"}


def test_reprovisioning_invalidates_the_previous_handout(tmp_path):
    """The documented recovery path when a handout leaks."""
    first = Roster.provision(tmp_path, count=2)
    old = list(csv.DictReader((tmp_path / HANDOUT_FILE).open(encoding="utf-8")))
    Roster.provision(tmp_path, count=2)
    reloaded = Roster.load(tmp_path)
    assert first.authenticates(old[0]["username"], old[0]["password"])
    assert not reloaded.authenticates(old[0]["username"], old[0]["password"])


def test_load_round_trips_a_provisioned_roster(tmp_path):
    Roster.provision(tmp_path, count=3)
    rows = list(
        csv.DictReader((tmp_path / HANDOUT_FILE).open(encoding="utf-8"))
    )
    reloaded = Roster.load(tmp_path)
    assert reloaded.usernames == ["user1", "user2", "user3"]
    assert reloaded.authenticates(rows[0]["username"], rows[0]["password"])


def test_load_without_a_roster_says_what_to_run(tmp_path):
    with pytest.raises(FileNotFoundError, match="workshop provision"):
        Roster.load(tmp_path)


def test_an_empty_workshop_is_refused(tmp_path):
    with pytest.raises(ValueError):
        Roster.provision(tmp_path, count=0)
