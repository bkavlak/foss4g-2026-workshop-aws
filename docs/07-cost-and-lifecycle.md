# Cost and lifecycle

## The mistake everyone makes once

You run the workshop. It goes well. You close the laptop.

Six weeks later the bill arrives and the cluster has been running the entire
time, because nothing in AWS ever stops on its own. There is no idle timeout on
a [NAT gateway](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html). Nobody emails you.

**The single most valuable habit in this document: `make down` on the same day.**
Not tomorrow. The same day, before you close the laptop.

## What bills, and how

The distinction that matters is **per-hour** versus **per-use**. Per-use charges
scale with what you did. Per-hour charges accrue whether or not anyone is
looking, and those are the ones that hurt.

| Resource | Bills | Roughly | Stops when |
|---|---|---|---|
| [EKS control plane](https://aws.amazon.com/eks/pricing/) | per hour | $0.10/hr — flat, any cluster size | cluster destroyed |
| [Nodes (spot)](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-spot-instances.html) | per hour | ~70% off on-demand; `make plan` prints the count | node group destroyed |
| NAT gateway | per hour **+ per GB** | ~$0.045/hr plus data processing | VPC destroyed |
| [Load balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/userguide/what-is-load-balancing.html) | per hour | ~$0.025/hr | Service deleted |
| EBS volumes (node disks) | per hour | per GB-month, and these are large | node destroyed |
| [S3 storage](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html) | per GB-month | 20 GB is cents | bucket emptied |
| ECR storage | per GB-month | cents | repository deleted |
| Data transfer out | per GB | small for a workshop | — |

Prices vary by region and change; treat these as orders of magnitude, not
quotes. Check the AWS pricing pages for your region before committing to a
budget.

### The rough shape for one day, 5 people

Control plane $2.40, two `m6i.xlarge` spot nodes about $3, NAT gateway $1.10
plus transfer, load balancer $0.60, EBS about $0.80, S3 and ECR in cents.
**Under $10** — *if* it runs for a day.

Left running for a month, the same stack is a couple of hundred dollars. The
difference is not the workshop. It is the forgetting.

## Where the money actually goes

Three things are worth understanding because they are counter-intuitive.

**The control plane is a floor.** $0.10/hr whether the cluster has one node or
fifty. A cluster left running with zero nodes still costs about $72/month. There
is no "scale to zero" for [EKS](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html).

**The NAT gateway is the sneaky one.** It exists so nodes in private subnets can
reach the internet — pulling images, pulling from S3. It charges per hour *and*
per GB processed. Twenty-five pods each syncing 20 GB is 500 GB through the NAT
if it routes that way.

This is a real optimisation you might want: an **S3 [VPC](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html) endpoint** (a gateway
endpoint, free) routes S3 traffic off the NAT entirely. For 500 GB that is worth
having. It would go in `modules/network`, and it is a good first change to make
to this repository once you are comfortable — small, self-contained, measurable.

**Node disks are sized per seat.** Because each seat syncs its own copy of the
dataset, `modules/capacity` sizes node disks as
`seats_per_node × seat.disk_gib × 1.15 + 40`. For the defaults — 5 people,
30 GB per seat — that is:

```
capacity_plan = {
  disk_gib       = 144
  instance_type  = "m6i.xlarge"
  nodes          = 2
  seats_per_node = 3
}
```

288 GB of [EBS](https://docs.aws.amazon.com/ebs/latest/userguide/what-is-ebs.html) in total: under a dollar a day, about $23 a month.
Run `make plan` and read `capacity_plan` rather than trusting this paragraph —
a `tofu test` pins these exact figures, but your seat size may not be the
default.

The number is worth watching as the headcount grows, because both the seat
count and the seats packed onto each node rise together. At 25 people the same
defaults produce 489 GB per node, nearly a terabyte in total. That is where the
[EFS](https://docs.aws.amazon.com/efs/latest/ug/whatisefs.html) alternative — one shared read-only copy instead of one per seat
— stops being theoretical. `modules/platform` is the only module that would
change.

## Spot instances

Nodes here use spot: spare AWS capacity at roughly 30% of on-demand, which AWS
can reclaim with two minutes' warning.

For a workshop this is close to free money. A reclaimed node drains its pods;
[JupyterHub](https://jupyterhub.readthedocs.io/en/stable/) reschedules them; a participant's seat restarts and their `/data`
re-syncs. They lose a minute and any unsaved notebook state. The node group
carries two nodes of headroom (`max_size = nodes + 2`) so there is somewhere to
go.

It is the right trade here and would be the wrong trade for anything holding
state you cannot lose. If you would rather not risk it, change `capacity_type`
in `modules/cluster/main.tf` to `"ON_DEMAND"` and pay roughly three times as
much.

## The lifecycle, and where each stage bills

```
make check       free, offline           ← run constantly
make roster      free, local             ← run once per workshop
make up          starts the meter        ← run on the day
   ... workshop ...
make down        stops the meter         ← run the same day
```

The staging inside `make up` exists because the image must be in [ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html) before
[Kubernetes](https://kubernetes.io/docs/concepts/overview/) can pull it, but ECR is created by the same apply. So: apply the
registry and bucket, push into them, then apply everything else.

### Verifying that `make down` actually finished

`destroy` can fail part-way — a load balancer that Kubernetes created is not
known to [OpenTofu](https://opentofu.org/docs/), and a VPC will not delete while it exists. Check, do not
assume:

```bash
make down
tofu -chdir=infra state list        # should print nothing
```

If it does not print nothing, read [the runbook](08-runbook.md#make-down-fails-part-way).

Then, in the console or CLI, confirm no EKS cluster, no NAT gateway and no load
balancer remain in the region. Two minutes now against a month of surprise.

## Guardrails worth setting up once

**A budget alert.** [AWS Budgets](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html), $50, email at 80%. Free, five minutes, and it
turns "found out six weeks later" into "found out on day two". Do this before
your first `make up`, not after.

**A [cost allocation tag](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/cost-alloc-tags.html).** `infra/versions.tf` already tags everything:

```hcl
default_tags {
  tags = {
    Workshop  = var.workshop_name
    ManagedBy = "opentofu"
  }
}
```

Activate `Workshop` as a cost allocation tag in the billing console and Cost
Explorer will show you exactly what this workshop cost, separated from
everything else in the account. Worth doing before the first run; tags only
apply to charges incurred after activation.

**One region.** Resources in a region you have forgotten about are invisible in
the console until you switch to it. Stay in `eu-central-1` unless you have a
reason.

## Free tier, briefly

There is no free tier for EKS. The control plane bills from the first hour, and
that is unavoidable with this architecture.

If cost were the dominant constraint, the alternative is k3s on a single EC2
instance — [Helm](https://helm.sh/docs/) still works, the chart is unchanged, and a `t3.large` gets close
to free-tier territory. What you give up is the managed control plane, node
autoscaling, and the fact that EKS is what participants will meet in the wild.
For teaching, that last point is worth the $2.40.

---

Next: [the runbook](08-runbook.md).
