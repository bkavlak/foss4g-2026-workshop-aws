# State, drift and blast radius

The concept with no Python equivalent, and the one that will bite you.

## Why state has to exist

You write:

```hcl
resource "aws_s3_bucket" "this" {
  bucket = var.name
}
```

You run `apply`. A bucket appears. You run `apply` again. How does [OpenTofu](https://opentofu.org/docs/) know
not to create a second one?

It could ask AWS "is there a bucket called `geo-workshop-data`?" — and for
buckets, which have globally unique names, that would almost work. But most
resources have no such natural key. There is nothing about a subnet that says
"I am the one from `module.network.private_subnets[1]`". AWS knows it as
`subnet-0a1b2c3d`, and nothing more.

So OpenTofu keeps a **[state file](https://opentofu.org/docs/language/state/)**: a JSON mapping from addresses in
your code to real identifiers and their last-known attributes.

```json
{
  "module": "module.dataset",
  "type": "aws_s3_bucket",
  "name": "this",
  "instances": [{ "attributes": { "id": "geo-workshop-data", "arn": "arn:aws:s3:::…" } }]
}
```

`module.dataset.aws_s3_bucket.this` ↔ `geo-workshop-data`. That is the whole
job, and every strange thing about OpenTofu follows from it.

## What follows from it

**State is the source of truth about *identity*, not about reality.** `plan`
refreshes: it reads state, asks AWS what those resources look like now, and
compares both against your code.

**If you lose state, OpenTofu forgets what it owns.** It does not go looking.
The next `apply` tries to create everything again — and you now have two VPCs,
one of which nothing manages. Recovering means [`tofu import`](https://opentofu.org/docs/language/import/), one
resource at a time.

**If you edit reality by hand, state goes stale.** That is drift.

**State contains everything, including secrets.** Covered in
[secrets and identity](05-secrets-and-identity.md), and it is the reason this
repository keeps plaintext passwords out of OpenTofu entirely.

## Where state lives, and why the default is a trap

By default: `infra/terraform.tfstate`, on your laptop, gitignored. Fine for a
workshop one person runs. Not fine the moment anyone else touches it, because:

- Two people applying at once corrupt it. There is no locking on a local file.
- Losing the laptop means losing the ability to run `make down`, which means
  the bill continues.

The fix is a remote [backend](https://opentofu.org/docs/language/settings/backends/configuration/) — an [S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html) bucket with a
DynamoDB lock table, or OpenTofu's native [state encryption](https://opentofu.org/docs/language/state/encryption/). This repository does not configure one,
deliberately: it would be a bucket that must exist before the code that creates
buckets can run, and for a single maintainer running a one-day workshop the
complexity is not repaid. **If a second person ever runs `apply`, add one
first.**

## Drift

Drift is reality and state disagreeing. Someone widens a
[security group](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html) in the
console at 09:00 to unblock a participant. Your code still says the old rule.

```bash
tofu plan -refresh-only    # what changed underneath me?
```

Then choose deliberately:

- The console change was right → put it in the code.
- The console change was wrong → `tofu apply` reverts it.

**What you must not do is nothing.** Undetected drift means your code is no
longer a description of reality, and the next apply — possibly weeks later, for
an unrelated reason — silently reverts a change someone made for a good reason.

The workshop-specific version of this: fixing something live in the cluster with
`kubectl edit` is fine and often correct at 09:15 with people waiting. Write
down what you did. Put it in the chart afterwards.

## Blast radius

The part that costs real money.

Some attribute changes can be applied in place. Others cannot, and the provider
must **destroy and recreate**. The plan tells you which, and this is the line to
read:

```
Plan: 2 to add, 0 to change, 2 to destroy.
```

`# forces replacement` in the diff is the phrase to look for:

```
  # module.cluster.module.eks.aws_eks_cluster.this must be replaced
  ~ name = "geo-workshop" -> "geo-workshop-v2"   # forces replacement
```

Renaming your workshop destroys the cluster. Everything in it goes: every
running seat, every participant's unsaved work. The plan said so, in a line that
is easy to skim past when there are 200 lines above it.

### Concrete traps in this repository

**`var.workshop_name` names almost everything.** Change it and you replace the
[VPC](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html), the cluster, the bucket and the [ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html) repository. It is not a label; it is an
identity.

**Changing `var.seat` can replace the node group.** A bigger seat changes the
capacity plan, which changes the instance type and disk size — both of which
force a new node group. Nodes drain, pods restart. Do it before people arrive,
not during a session.

**`force_destroy = true` on the dataset bucket** means `make down` deletes the
data without complaint. That is correct here — the bucket holds a copy of
something you have locally in `data/` — but the same flag on a bucket holding
the only copy of something is how people lose data permanently.

### Habits that cost nothing

1. **Read the summary line of every plan.** If "to destroy" is not zero, know
   which resources and why before typing yes.
2. **Rename nothing mid-workshop.** Not the workshop, not the namespace, not the
   release.
3. `tofu plan -out=tfplan` then `tofu apply tfplan` applies exactly what you
   reviewed, with no chance of something changing in between.
4. For anything that must never be destroyed by accident:

   ```hcl
   lifecycle { prevent_destroy = true }
   ```

   (the [`lifecycle` meta-argument](https://opentofu.org/docs/language/meta-arguments/lifecycle/))

   An apply that would destroy it fails instead. Nothing in this repository uses
   it, because everything here is meant to be disposable — but that is a
   decision, not an oversight.

## The mental model to keep

> State is a cache of identity. Your code is the intent. Reality is the truth.
> `plan` is the only thing that shows you all three at once, and it costs
> nothing to run.

---

Next: [secrets and identity](05-secrets-and-identity.md).
