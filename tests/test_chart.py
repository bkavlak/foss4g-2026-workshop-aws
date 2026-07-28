"""What the chart actually renders into the cluster.

These run `helm template` locally: no Kubernetes API is contacted. They cover
the objects this chart owns, and specifically the promise that plaintext never
leaves the maintainer's machine.
"""

import json

import pytest

from workshop import credentials

pytestmark = pytest.mark.usefixtures("render_chart")


def _values(roster=None, dataset_uri="", role_arn=""):
    return json.dumps(
        {
            "roster": roster or {},
            "dataset": {
                "uri": dataset_uri,
                "awsRoleArn": role_arn,
                "mountPath": "/data",
            },
        }
    )


def test_roster_secret_carries_only_verifiers(render_chart):
    credential = credentials.mint()
    values = _values(roster={"user1": credential.verifier})

    secret = render_chart(values, "templates/roster-secret.yaml")
    document = secret["stringData"]["roster.json"]

    assert credential.password not in document
    assert (
        json.loads(document)["participants"]["user1"]["hash"]
        == credential.verifier["hash"]
    )


def test_rendered_roster_is_readable_by_the_shipped_authenticator(
    render_chart, authenticator
):
    """Secret, mounted .py file and minting tool agree end to end."""
    credential = credentials.mint()
    secret = render_chart(
        _values(roster={"user1": credential.verifier}),
        "templates/roster-secret.yaml",
    )
    roster = json.loads(secret["stringData"]["roster.json"])["participants"]

    assert (
        authenticator.resolve(roster, "user1", credential.password) == "user1"
    )
    assert authenticator.resolve(roster, "user1", "wrong") is None


def test_participant_account_gets_dataset_access_only_when_there_is_a_dataset(
    render_chart,
):
    with_data = render_chart(
        _values(
            dataset_uri="s3://bucket", role_arn="arn:aws:iam::1:role/reader"
        ),
        "templates/participant-serviceaccount.yaml",
    )
    assert with_data["metadata"]["annotations"][
        "eks.amazonaws.com/role-arn"
    ].endswith("reader")

    without_data = render_chart(
        _values(), "templates/participant-serviceaccount.yaml"
    )
    assert "annotations" not in without_data["metadata"]


def test_authenticator_configmap_ships_the_real_file(render_chart):
    rendered = render_chart(_values(), "templates/roster-authenticator.yaml")
    source = rendered["data"]["roster_authenticator.py"]
    assert "class RosterAuthenticator" in source
    assert "hashlib.scrypt" in source
