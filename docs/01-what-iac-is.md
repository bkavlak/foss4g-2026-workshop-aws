# What Infrastructure as Code actually is

## The one-sentence version

You write down the infrastructure you want; a tool works out the difference
between that and what exists, and closes the gap.

That is the whole idea. Everything else — providers, state, drift, modules — is
machinery in service of it.

## The shift that trips people up

Almost all the Python you have written is **imperative**. You say what to do,
in order:

```python
ds = gdal.Open("input.tif")
band = ds.GetRasterBand(1)
array = band.ReadAsArray()
```

Run it twice and you do the work twice. Run it half-way and you have a
half-finished job that you must reason about to resume.

[OpenTofu](https://opentofu.org/docs/) is **declarative**. You say what a [resource](https://opentofu.org/docs/language/resources/) should be:

```hcl
resource "aws_s3_bucket" "this" {
  bucket = var.name
}
```

Nowhere do you say "create the bucket". You say the bucket exists. Running that
once creates it; running it again does nothing, because it already exists.
Running it after someone deleted the bucket by hand creates it again.

The closest thing in your world is probably `make`, or a build system: you
declare that `output.tif` depends on `input.tif`, and the tool decides whether
any work is needed. Or if you have used one: a database migration tool, which
you point at a schema and it computes the ALTER statements.

**The practical consequence:** you stop asking "what should this script do?"
and start asking "what should be true when this finishes?". Ordering is
something you almost never specify. OpenTofu infers it from the references
between resources — because `modules/cluster` reads
`module.network.node_subnet_ids`, the network is built first. Nobody wrote that
down.

## The three commands

```bash
tofu plan      # what would change, and why. Changes nothing.
tofu apply     # make it so
tofu destroy   # unmake it
```

Reference: [`plan`](https://opentofu.org/docs/cli/commands/plan/), [`apply`](https://opentofu.org/docs/cli/commands/apply/),
[`destroy`](https://opentofu.org/docs/cli/commands/destroy/).

`plan` is the one to internalise. It is a dry run that reads reality, compares
it to your code, and prints a diff:

```
  # module.dataset.aws_s3_bucket.this will be created
  + resource "aws_s3_bucket" "this" {
      + bucket = "geo-workshop-data"
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

Read the last line of every plan before you apply. **"0 to destroy" is the
number that matters** — see [blast radius](04-state-and-drift.md).

## What a provider is

OpenTofu itself knows nothing about AWS. A **[provider](https://opentofu.org/docs/language/providers/)** is a plugin that
translates `resource "aws_s3_bucket"` into API calls. `infra/versions.tf`
declares the two this repository uses:

```hcl
required_providers {
  aws  = { source = "hashicorp/aws",  version = "~> 5.75" }
  helm = { source = "hashicorp/helm", version = "~> 2.16" }
}
```

Think of them as libraries with a fixed interface, the way `rasterio` and
`fiona` are both bindings over [GDAL](https://gdal.org/en/stable/). `tofu init` downloads them.

## What a module is

A [module](https://opentofu.org/docs/language/modules/) is a directory of `.tf` files with inputs (`variable`) and
outputs (`output`).
That is genuinely all. It is a function: arguments in, values out, everything
else hidden.

```hcl
module "cluster" {
  source = "./modules/cluster"

  name       = var.workshop_name
  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.node_subnet_ids
  workload   = { replicas = 5, vcpu = 1, memory_gib = 4, disk_gib = 30 }
}
```

`module.cluster.endpoint` is then available to whoever needs it, exactly like a
return value. `infra/modules/capacity/` is the purest example in this
repository: it declares no provider and creates nothing. It takes a description
of a workload and returns a description of hardware. It is a pure function that
happens to be written in HCL, which is precisely why its tests need no AWS
account at all.

## The two things with no Python analogy

1. **[State](https://opentofu.org/docs/language/state/).** OpenTofu keeps a file recording which real resource corresponds
   to which block in your code. Without it, it cannot tell "create a bucket"
   from "you already have that bucket". This is where most confusion lives, so
   it gets [its own document](04-state-and-drift.md).

2. **Nothing is free.** A typo in Python costs you a traceback. A typo here can
   cost you a [NAT gateway](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html) running all month, or delete a cluster. The feedback
   loop has a price attached, which is why so much of this repository is built
   to be testable without spending anything.

## Why HCL and not Python

You will reasonably wonder why this is not just Python calling boto3. It could
be — that is what AWS CDK and Pulumi do. The trade:

- **Declarative (OpenTofu's [HCL](https://opentofu.org/docs/language/syntax/configuration/)):** limited language, so a `plan` can be
  computed reliably before anything happens. You can always see what will change.
- **Imperative (CDK, Pulumi, a boto3 script):** the full language, so you can
  express anything — but the tool must run your code to find out what it does,
  and a plain boto3 script has no plan at all.

For infrastructure that a workshop maintainer clicks once and must trust, the
predictable diff is worth more than the expressive language. Where real
computation was genuinely needed — packing seats onto instances —
`modules/capacity` shows how far HCL stretches, and it is roughly the limit.

---

Next: [a tour of this repository](02-the-tour.md).
