# Testing and confidence

Testing infrastructure is unlike testing a [GDAL](https://gdal.org/en/stable/) pipeline in one way that changes
everything: **running the code costs money and takes twenty minutes.** You
cannot iterate your way to correctness. So the question is not "how do I test
this?" but "how much can I learn without applying?"

Quite a lot, as it turns out — and it is important to be precise about where
that stops.

## The layers here

```
make lint        ruff, pylint, helm, tofu   ~10s   style and correctness
make typecheck   mypy --strict over src/     ~5s   types
make security    bandit, checkov            ~20s   Python and infrastructure
make test        40 pytest tests             ~3s   Python, and what Helm renders
make test-infra  12 tofu runs               ~10s   packing rules, IAM, values
```

`make check` runs all of them, and `make setup` wires the same tools into git
hooks. None contacts AWS. None needs credentials.

Three of these earn their place by having already caught something:

- **[pylint](https://pylint.readthedocs.io/en/stable/)** found `assert hub_says == local_says is True` in this suite. That
  is a chained comparison — `(a == b) and (b is True)` — not the conjunction it
  reads as. A test that passes for the wrong reason is worse than no test.
- **the link test** found a concept sent to two different pages from two
  different documents, on its first run. Documentation rots the way code
  does; the difference is that nothing usually notices.
- **[checkov](https://www.checkov.io/)** found that nothing aborted incomplete S3 multipart uploads. A
  failed 20 GB `aws s3 sync` leaves parts that bill as storage forever and do
  not appear in a bucket listing — the exact "destroyed, still costing money"
  failure that [cost and lifecycle](07-cost-and-lifecycle.md) warns about.

## Layer 1: ordinary Python tests

`src/workshop/` is ordinary Python and gets ordinary tests. Nothing novel —
except in what they assert. Compare:

```python
def test_minted_password_verifies():
    credential = credentials.mint()
    assert credentials.verify(credential.verifier, credential.password)
```

with:

```python
def test_no_plaintext_password_reaches_the_cluster_document(tmp_path):
    Roster.provision(tmp_path, count=6)
    document = (tmp_path / ROSTER_FILE).read_text(encoding="utf-8")
    rows = list(
        csv.DictReader((tmp_path / HANDOUT_FILE).open(encoding="utf-8"))
    )
    for row in rows:
        assert row["password"] not in document
```

The first tests a function. The second tests a *promise*: that the file shipped
to the cluster contains no plaintext. That promise is the reason the design
exists, and it is now impossible to break silently.

Aim your tests at the promises, not the functions. It is the difference between
a suite that catches typos and one that catches design regressions.

## Layer 2: `helm template`, mocking nothing

`helm template` renders a chart to YAML locally and contacts no cluster. So
`tests/test_chart.py` runs the real templating engine over the real chart and
asserts on the output:

```python
def test_participant_account_gets_dataset_access_only_when_there_is_a_dataset(
    render_chart,
):
    with_data = render_chart(..., "templates/participant-serviceaccount.yaml")
    assert with_data["metadata"]["annotations"][
        "eks.amazonaws.com/role-arn"
    ].endswith("reader")

    without_data = render_chart(
        _values(), "templates/participant-serviceaccount.yaml"
    )
    assert "annotations" not in without_data["metadata"]
```

This catches the whole class of [Helm](https://helm.sh/docs/) bugs that are otherwise found by deploying:
wrong indentation, a conditional that fires the wrong way, a value that silently
renders as empty.

The best test in that file spans three components at once:

```python
def test_rendered_roster_is_readable_by_the_shipped_authenticator(
    render_chart, authenticator
):
    credential = credentials.mint()
    secret = render_chart(_values(roster={"user1": credential.verifier}), ...)
    roster = json.loads(secret["stringData"]["roster.json"])["participants"]
    assert (
        authenticator.resolve(roster, "user1", credential.password) == "user1"
    )
```

A password minted by the CLI, serialised through the Helm template, and checked
by the file the hub actually mounts. No cluster involved. If any of the three
changes incompatibly, this fails in two seconds rather than at 09:05 with an
audience.

## Layer 3: `tofu test` with mocked providers

[OpenTofu](https://opentofu.org/docs/) can [run test files](https://opentofu.org/docs/cli/commands/test/) with
the provider replaced by a [mock](https://opentofu.org/docs/language/tests/mocking/) — no API calls, no
credentials, no resources:

```hcl
mock_provider "aws" {}

run "images_are_scanned_and_old_ones_expire" {
  command = plan
  module { source = "./modules/registry" }
  variables { name = "test-workshop" }

  assert {
    condition     = aws_ecr_repository.this.image_scanning_configuration[0].scan_on_push
    error_message = "Participant images should be scanned when pushed."
  }
}
```

### The catch that shaped this repository

A mocked provider returns fake values for anything the *provider* computes. So
you can only assert on things knowable from your configuration.

This bit during development. The [IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction.html) trust policy was originally built with
`data "aws_iam_policy_document"` — the idiomatic approach. But that data source
is evaluated by the AWS provider, so under a mock it returns nonsense, and the
test could not assert on who was allowed to do what.

Rewriting it as `jsonencode({...})` made the policy known at plan time, and
therefore assertable:

```hcl
assert {
  condition = strcontains(
    aws_iam_role.reader.assume_role_policy,
    "system:serviceaccount:workshop:workshop-participant",
  )
  error_message = "Any pod in the cluster could read the dataset, not just participant seats."
}
```

**Testability changed the design, and the design got simpler.** That is usually
how it goes, and it is a reason to take the constraint seriously rather than
route around it.

### Pure computation needs no mock at all

`modules/capacity` declares no provider and creates nothing, so its tests are
just... tests:

```hcl
run "seats_are_packed_rather_than_given_a_node_each" {
  command = plan
  module { source = "./modules/capacity" }
  variables { workload = { replicas = 25, vcpu = 1, memory_gib = 4, disk_gib = 30 } }

  assert {
    condition     = output.plan.seats_per_node > 1
    error_message = "A 1 vCPU / 4 GiB seat must share a node with others."
  }
}
```

That test found a real bug. The original packer chose the smallest instance that
fits one seat, which would have given 25 participants 25 separate nodes. Without
the
arithmetic being extracted into a provider-free module, that would have been
discovered on a bill.

**The lesson generalises:** separate the deciding from the doing. Decisions are
cheap to test; API calls are not.

## What these tests do not prove

Be precise about this. Passing `make check` proves the code is internally
consistent. It does **not** prove:

- **That an apply succeeds.** [Service quotas](https://docs.aws.amazon.com/general/latest/gr/aws_service_limits.html), an account with no default [VPC](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html),
  an unavailable [Kubernetes](https://kubernetes.io/docs/concepts/overview/) version, IAM permissions your user lacks.
- **That the IAM policy actually permits what you think.** The test checks the
  policy *says* `s3:GetObject`. Whether [STS](https://docs.aws.amazon.com/STS/latest/APIReference/welcome.html) grants it, whether an SCP overrides
  it, whether a bucket policy denies it — only a real call answers that.
- **That spot capacity exists** for `m6i.4xlarge` in your region this morning.
- **That the image builds**, or that GDAL and `geopandas` coexist in it.
  `docker build` is the only test for that, and it is not in `make check`
  because it needs a Docker daemon and several minutes. The [Dockerfile](https://docs.docker.com/reference/dockerfile/) ends
  with a smoke import of `osgeo`, `geopandas` and `rasterio` so that a broken
  combination fails the build rather than a participant's first cell — but you
  still have to run the build.
- **That everyone can log in at once.** Nothing here load-tests the hub.

## What to do about the gap

**Rehearse.** Run the whole thing end to end, once, days before, with
`PARTICIPANTS=2`. It costs a few dollars and a couple of hours, and it converts
every item on that list from unknown to known:

```bash
make check
make roster PARTICIPANTS=2
make up PARTICIPANTS=2
make url
# log in as user1. open a notebook. import gdal. list /data.
make down
```

Then re-run `make up` with the real headcount on the day.

Confidence in infrastructure comes from having done it before, not from a green
test suite. The suite's job is to make sure the rehearsal is the *first* time
you spend money, not the fifth.

---

Next: [cost and lifecycle](07-cost-and-lifecycle.md).
