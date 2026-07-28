# Understanding this repository

You know Python and [GDAL](https://gdal.org/en/stable/). This folder is about the other half — the part that
turns a container image into five people typing at a browser, and the ways that
half goes wrong.

Everything here uses the code in this repository as its worked example, so no
document is abstract for long. Read in order the first time.

| | | |
|---|---|---|
| 0 | [Connecting your AWS account](00-connecting-aws.md) | Start here if you have never set up the AWS CLI |
| 1 | [What Infrastructure as Code actually is](01-what-iac-is.md) | The mental model, in terms you already have |
| 2 | [A tour of this repository](02-the-tour.md) | Every module, in the order they depend on each other |
| 3 | [Kubernetes and Helm, minimally](03-helm-and-kubernetes.md) | Enough to read `charts/workshop/` without guessing |
| 4 | [State, drift and blast radius](04-state-and-drift.md) | The concept with no Python equivalent, and the one that bites |
| 5 | [Secrets and identity](05-secrets-and-identity.md) | Why passwords never reach the state file, and what IRSA does |
| 6 | [Testing and confidence](06-testing.md) | What mocked tests prove, and what only money proves |
| 7 | [Cost and lifecycle](07-cost-and-lifecycle.md) | What bills by the hour, and the classic expensive mistake |
| 8 | [Runbook: when it breaks live](08-runbook.md) | Symptom → diagnosis → command. Keep this open during the workshop |
| — | [Glossary](glossary.md) | Every term, one line each |

## If nothing is set up yet

[Connecting your AWS account](00-connecting-aws.md). It assumes no prior
knowledge, explains every prompt, and shows what to type.

## If you only read one thing before the workshop

[The runbook](08-runbook.md). Then skim
[cost and lifecycle](07-cost-and-lifecycle.md) so that `make down` is muscle
memory by the end of the day.

## Following a concept further

The first time a document mentions a concept — a [VPC](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html), a
[LoadBalancer](https://kubernetes.io/docs/concepts/services-networking/service/), a [state file](https://opentofu.org/docs/language/state/) — it links to
that project's own documentation. Later mentions do not, so the prose stays
readable.

The [glossary](glossary.md) is the index: every term there carries the same
link, so if you meet a word mid-document and want the authoritative source,
look it up there rather than hunting for its first mention. Terms specific to
this repository — seat, roster, handout, verifier, capacity plan — have no
link, because there is nothing upstream to point at.

## A note on how these are written

Where a document makes a claim about this repository, it names the file. If a
document and the code disagree, the code is right and the document is a bug —
`make check` will not catch that, so please fix the prose when you change the
design.
