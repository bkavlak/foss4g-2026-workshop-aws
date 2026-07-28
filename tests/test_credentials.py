"""The credential policy: what a minted password is worth and what proves it."""

import pytest

from workshop import credentials


def test_minted_password_verifies():
    credential = credentials.mint()
    assert credentials.verify(credential.verifier, credential.password)


def test_wrong_password_is_rejected():
    credential = credentials.mint()
    assert not credentials.verify(
        credential.verifier, credential.password + "x"
    )
    assert not credentials.verify(credential.verifier, "")


def test_verifier_never_carries_the_password():
    credential = credentials.mint()
    assert credential.password not in str(credential.verifier)


def test_each_mint_is_independent():
    """Two participants who happen to choose nothing must still differ."""
    first, second = credentials.mint(), credentials.mint()
    assert first.password != second.password
    assert first.verifier["salt"] != second.verifier["salt"]
    assert not credentials.verify(first.verifier, second.password)


def test_passwords_avoid_ambiguous_characters():
    """Participants type these off a printed handout."""
    forbidden = set("l1IO0")
    for _ in range(20):
        password = credentials.mint().password
        assert not set(password) & forbidden


def test_password_is_long_enough_to_survive_a_public_url():
    assert len(credentials.mint().password) >= 12


@pytest.mark.parametrize(
    "verifier",
    [
        {},
        {"salt": "zz", "hash": "aa", "n": 16384, "r": 8, "p": 1},
        {"salt": "00", "hash": "00"},
        {"salt": "00", "hash": "00", "n": "many", "r": 8, "p": 1},
        None,
    ],
)
def test_broken_verifier_is_a_failed_login_not_a_crash(verifier):
    """Every caller is a login path; a raised exception there is an outage."""
    assert credentials.verify(verifier or {}, "anything") is False


def test_cost_parameters_travel_with_the_verifier():
    """So that a roster minted today still works after the policy is raised."""
    verifier = credentials.mint().verifier
    assert {"n", "r", "p"} <= set(verifier)
