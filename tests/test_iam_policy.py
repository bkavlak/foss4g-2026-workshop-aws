"""The hand-off IAM policy.

`docs/iam/workshop-provisioner-policy.json` is pasted into the AWS console by
somebody who is not us, so a defect in it surfaces as a stranger's failed
`tofu apply`. These checks are cheap and catch the two ways it realistically
breaks: malformed structure, and quietly growing past what IAM will accept.
"""

import json
from pathlib import Path

import pytest

# A pytest fixture is referenced by a parameter of the same name, which Pylint
# reads as shadowing. That is the idiom, not a defect.
# pylint: disable=redefined-outer-name

POLICY = (
    Path(__file__).resolve().parents[1]
    / "docs"
    / "iam"
    / "workshop-provisioner-policy.json"
)

# An AWS managed policy document may not exceed this, measured with whitespace
# removed.
IAM_MANAGED_POLICY_LIMIT = 6144


@pytest.fixture(scope="module")
def policy():
    return json.loads(POLICY.read_text(encoding="utf-8"))


def test_it_fits_in_a_managed_policy(policy):
    """AWS measures the document with whitespace stripped."""
    compact = json.dumps(policy, separators=(",", ":"))
    assert len(compact) <= IAM_MANAGED_POLICY_LIMIT, (
        f"policy is {len(compact)} characters, over the "
        f"{IAM_MANAGED_POLICY_LIMIT} limit; split it or widen an action"
    )


def test_every_statement_is_complete(policy):
    """A statement missing Effect or Resource is silently ignored by IAM."""
    assert policy["Version"] == "2012-10-17"
    for statement in policy["Statement"]:
        assert set(statement) == {"Sid", "Effect", "Action", "Resource"}
        assert statement["Effect"] == "Allow"
        assert statement["Action"], f"{statement['Sid']} grants nothing"


def test_no_statement_grants_everything(policy):
    """`Action: *` would make the whole document pointless."""
    for statement in policy["Statement"]:
        actions = statement["Action"]
        assert "*" not in actions, f"{statement['Sid']} grants every action"
        for action in actions:
            assert action != "*" and not action.startswith("*")


def test_the_services_the_stack_needs_are_all_covered(policy):
    """Guards against an action list being trimmed below what a plan needs."""
    granted = {
        action.split(":")[0]
        for statement in policy["Statement"]
        for action in statement["Action"]
    }
    required = {
        "autoscaling",
        "ec2",
        "ecr",
        "eks",
        "iam",
        "kms",
        "logs",
        "s3",
        "ssm",
        "sts",
    }
    assert required <= granted, (
        f"no permissions for: {sorted(required - granted)}"
    )
