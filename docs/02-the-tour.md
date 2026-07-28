# A tour of this repository

Follow one participant's request backwards and you touch everything. Someone
opens a URL, types `user3` and a password, and a minute later has a JupyterLab
tab with [GDAL](https://gdal.org/en/stable/) and 20 GB of data. This document walks the pieces that make that
true, in the order they depend on each other.

## The map

```
  workshop provision  ──▶  roster/roster.json  ──┐
                           roster/handout.csv    │  (paper, stays on your laptop)
                                                 ▼
  docker/  ──▶  ECR  ──┐                    OpenTofu (infra/)
  data/    ──▶  S3   ──┴──────────────────▶  ├─ network   VPC, subnets, NAT
                                             ├─ registry  ECR + retention
                                             ├─ cluster   EKS, sized from headcount
                                             ├─ dataset   S3 bucket + read grant
                                             └─ platform  Helm release
                                                            │
                                                            ▼
                                              charts/workshop  (JupyterHub)
```

## 1. `src/workshop/` — the credentials

Ordinary Python, and the only part of this repository that runs on your laptop
rather than in AWS.

`credentials.py` owns one decision: what a password is worth. It picks the
alphabet (no `l`, `1`, `I`, `O`, `0` — people read these off paper), the length,
and the [scrypt](https://docs.python.org/3/library/hashlib.html) parameters that protect it. Two functions: `mint()` and
`verify()`.

`roster.py` owns a different decision: what a workshop's worth of accounts looks
like on disk. `Roster.provision()` mints, writes `handout.csv` at mode 0600, and
returns a `Roster` that holds **only verifiers**. There is deliberately no way
to get a plaintext password back out of a `Roster` object — the type cannot
represent one, so no future edit can accidentally log one.

```bash
make roster PARTICIPANTS=5
```

## 2. `docker/` — the environment

A [Dockerfile](https://docs.docker.com/reference/dockerfile/) on `ghcr.io/osgeo/gdal:ubuntu-small-3.13.2`. That base is chosen
for a specific reason: GDAL 3.13's Ubuntu image is built on Ubuntu 26.04, whose
system interpreter is Python 3.14 and whose `osgeo` bindings are compiled
against it. GDAL and the required Python version arrive together instead of
being reconciled by hand.

The Python stack is installed into a virtualenv created with
`--system-site-packages`, so the base image's `osgeo` bindings stay visible
while nothing fights Ubuntu's externally-managed-environment marker.

One thing that confuses people: `from osgeo import gdal` reports the image's
GDAL 3.13.2, but `rasterio` and `pyogrio` bundle their own GDAL inside their
wheels and report a different version. Both work. They are not the same library.

Note what is *not* here: the data. A 20 GB image takes minutes to push, minutes
to pull on every node, and has to be rebuilt whenever the data changes. See
step 6.

## 3. `infra/modules/network` — where things live

A [VPC](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html), three availability zones, private subnets for nodes, public subnets for
the load balancer, one [NAT gateway](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html).

Its entire interface is a name:

```hcl
module "network" {
  source = "./modules/network"
  name   = var.workshop_name
  region = var.region
}
```

Address ranges, AZ selection and the `kubernetes.io/role/elb` subnet tags are
decisions it owns. That last one is the reason this module exists rather than
being inlined: [EKS](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html) reads those tags to decide where to put load balancers, and
getting them wrong fails much later with an error that never mentions subnets.

## 4. `infra/modules/capacity` — how much hardware

No providers. No resources. Nothing to create. It takes:

```hcl
workload = { replicas = 5, vcpu = 1, memory_gib = 4, disk_gib = 30 }
```

and returns which instance type, how many nodes, how many seats fit on each,
and how big the disks must be. Read `main.tf` — it is the most Python-like file
in `infra/`, and the comment in it records a real bug: the first version picked
the smallest instance that fits *one* seat, so a 25-person workshop would have
been billed for 25 machines instead of 2.

## 5. `infra/modules/cluster` — the cluster

Asked for a workload, returns a cluster. It calls `capacity` internally, so
callers never see an instance type. Spot instances, the addon set, [IRSA](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html) and
node disk sizing are all consequences it hides.

It builds on `terraform-aws-modules/eks/aws`, a community module. Writing the
EKS [IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction.html) roles by hand is several hundred lines that everyone gets wrong the same
way; this wrapper is worth its existence because it converts *"how many people
are coming?"* into a cluster, which the upstream module does not.

## 6. `infra/modules/dataset` — the data and the right to read it

An S3 bucket plus an IAM role, in one module because they are one decision. A
bucket nobody may read is useless; a role granting access to nothing is
meaningless. Splitting them would let a caller create one without the other.

`make data-push` mirrors `data/` into the bucket. At pod start an [init container](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)
runs `aws s3 sync` into `/data`, and JupyterLab does not start until it
finishes — so a participant never sees a half-populated directory.

The IAM role is the interesting half; see
[secrets and identity](05-secrets-and-identity.md) for what IRSA is doing.

## 7. `infra/modules/platform` — the translation layer

The only place where workshop vocabulary becomes [JupyterHub](https://jupyterhub.readthedocs.io/en/stable/) vocabulary. It
deploys `charts/workshop` and renders `values.yaml.tftpl` with the handful of
facts that vary per workshop: the image, the seat size, the dataset URI, the
roster.

This is where the init container is conditionally included:

```
%{ if dataset.uri != "" ~}
    initContainers:
      - name: dataset-sync
        ...
%{ endif ~}
```

Leave `data/` empty and there is no init container at all, rather than one that
syncs from nowhere and hangs.

## 8. `infra/main.tf` — the composition root

Wiring, and nothing else. The only logic in it is reading the roster, and one
guard:

```hcl
check "roster_matches_headcount" {
  assert {
    condition = length(local.roster) >= var.participant_count
    ...
  }
}
```

A cluster sized for 5 people with a roster of 2 logins is a problem you would
otherwise discover in front of an audience.

## 9. `charts/workshop` — what participants touch

Covered in [Kubernetes and Helm](03-helm-and-kubernetes.md).

## Where to start reading

`infra/modules/capacity/main.tf`, then `infra/main.tf`, then
`src/workshop/credentials.py`. The first is pure computation, the second is pure
wiring, and the third is a domain you already know. Everything else is easier
once those three are familiar.

---

Next: [Kubernetes and Helm, minimally](03-helm-and-kubernetes.md).
