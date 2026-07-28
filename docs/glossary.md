# Glossary

One line each. Terms you will meet in this repository or while reading about it.

## Infrastructure as Code

**[Apply](https://opentofu.org/docs/cli/commands/apply/)** — execute a plan; make reality match the code.

**[Backend](https://opentofu.org/docs/language/settings/backends/configuration/)** — where state is stored. Local file by default; S3 with locking for
teams.

**[Declarative](https://opentofu.org/docs/)** — you describe the end state, the tool works out the steps.
Opposite of imperative.

**[Drift](https://opentofu.org/docs/language/state/)** — reality and state disagreeing, usually because someone changed
something by hand.

**[HCL](https://opentofu.org/docs/language/syntax/configuration/)** — HashiCorp Configuration Language, the syntax OpenTofu configuration is
written in.

**[Idempotent](https://opentofu.org/docs/)** — running it twice has the same effect as running it once.

**[Module](https://opentofu.org/docs/language/modules/)** — a directory of configuration with inputs and outputs. A function.

**[OpenTofu](https://opentofu.org/docs/)** — the open-source fork of Terraform, and what this repository uses.
Commands and syntax are compatible.

**[Plan](https://opentofu.org/docs/cli/commands/plan/)** — a dry run that reads reality, compares it to the code, and prints the
diff. Changes nothing.

**[Provider](https://opentofu.org/docs/language/providers/)** — a plugin that translates resource blocks into API calls for one
platform.

**[Replacement](https://opentofu.org/docs/cli/commands/apply/)** — when a change cannot be applied in place, so the resource is
destroyed and recreated. Shown as `# forces replacement` in a plan.

**[Resource](https://opentofu.org/docs/language/resources/)** — one thing the provider manages: a bucket, a subnet, a role.

**[State](https://opentofu.org/docs/language/state/)** — the file mapping addresses in your code to real resource IDs.

**[tofu import](https://opentofu.org/docs/language/import/)** — adopt an existing resource into state, so OpenTofu manages
it from then on.

**[prevent_destroy](https://opentofu.org/docs/language/meta-arguments/lifecycle/)** — a lifecycle setting that makes an apply fail rather than
destroy a resource.

**[mock_provider](https://opentofu.org/docs/language/tests/mocking/)** — a test-only replacement for a provider, so tests run
without credentials or API calls.

## AWS

**[AMI](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AMIs.html)** — a machine image; what an EC2 instance boots from.

**[ARN](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference-arns.html)** — Amazon Resource Name. The globally unique identifier for a resource.

**[Availability Zone (AZ)](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-regions-availability-zones.html)** — an isolated datacentre within a region. This
repository spreads across three.

**[EBS](https://docs.aws.amazon.com/ebs/latest/userguide/what-is-ebs.html)** — network-attached block storage. Node disks are EBS volumes.

**[ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html)** — Elastic Container Registry. Where the participant image is pushed.

**[EFS](https://docs.aws.amazon.com/efs/latest/ug/whatisefs.html)** — a shared network filesystem, mountable by many pods at once. The
alternative to per-seat dataset copies.

**[EKS](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html)** — Elastic Kubernetes Service. The managed control plane, $0.10/hr.

**[IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction.html)** — Identity and Access Management. Who may do what.

**[IRSA](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)** — IAM Roles for Service Accounts. Lets a pod assume an IAM role using a
signed token instead of stored keys.

**[NAT gateway](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html)** — lets resources in private subnets reach the internet. Bills
per hour *and* per GB.

**[OIDC provider](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_oidc.html)** — the identity provider the cluster runs, which AWS trusts to
vouch for pods. The foundation of IRSA.

**[On-demand](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-on-demand-instances.html)** — the standard, uninterruptible instance price.

**[Region](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-regions-availability-zones.html)** — a geographic grouping of availability zones, e.g. `eu-central-1`.

**[S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html)** — object storage. Where the dataset lives.

**[Security group](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html)** — a stateful firewall attached to a network interface.

**[Spot](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-spot-instances.html)** — spare capacity at a large discount, reclaimable with two minutes'
notice. What this repository uses for nodes.

**[STS](https://docs.aws.amazon.com/STS/latest/APIReference/welcome.html)** — Security Token Service. Issues the temporary credentials IRSA hands
to a pod.

**[Subnet](https://docs.aws.amazon.com/vpc/latest/userguide/configure-subnets.html)** — an address range within a VPC, tied to one availability zone.
Private subnets have no direct internet route.

**[Trust policy](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_terms-and-concepts.html)** — the document saying who may assume an IAM role, as opposed to
what the role may then do.

**[VPC](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html)** — a private network. Everything in this repository lives in one.

## Kubernetes and Helm

**[Chart](https://helm.sh/docs/topics/charts/)** — a Helm package: templated YAML plus default values.

**[ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/)** — non-sensitive key–value data, mountable as files.

**[Control plane](https://kubernetes.io/docs/concepts/overview/components/)** — the API server and controllers. Managed by EKS here.

**[Culler](https://z2jh.jupyter.org/en/stable/)** — JupyterHub's reaper for idle seats. Set to one hour.

**[`helm template`](https://helm.sh/docs/helm/helm_template/)** — render a chart to YAML locally, contacting nothing.

**[Init container](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)** — a container that runs to completion before the main
containers start. Used here to sync `/data`.

**[Namespace](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/)** — a naming scope within a cluster. This workshop lives in
`workshop`.

**[Node](https://kubernetes.io/docs/concepts/architecture/nodes/)** — a machine that runs pods. An EC2 instance here.

**[Node group](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html)** — a managed set of identically configured nodes.

**[Pod](https://kubernetes.io/docs/concepts/workloads/pods/)** — the smallest deployable unit: one or more containers scheduled
together.

**[Release](https://helm.sh/docs/glossary/)** — an installed instance of a chart, with a name.

**[Secret](https://kubernetes.io/docs/concepts/configuration/secret/)** — key–value data, base64-encoded. **Encoded, not encrypted.**

**[Service](https://kubernetes.io/docs/concepts/services-networking/service/)** — a stable address in front of a set of pods. `type: LoadBalancer`
provisions a real AWS load balancer.

**[ServiceAccount](https://kubernetes.io/docs/concepts/security/service-accounts/)** — the identity a pod runs as, inside and (via IRSA) outside
the cluster.

**[Subchart](https://helm.sh/docs/chart_template_guide/subcharts_and_globals/)** — a chart another chart depends on. JupyterHub is a subchart here.

**[Values](https://helm.sh/docs/chart_template_guide/values_files/)** — a chart's parameters.

**[z2jh](https://z2jh.jupyter.org/en/stable/)** — "Zero to JupyterHub", the official JupyterHub Helm chart.

## This repository

**Capacity plan** — what `modules/capacity` returns: instance type, node count,
seats per node, disk size.

**Handout** — `roster/handout.csv`. Plaintext passwords, mode 0600, your laptop
only.

**Roster** — `roster/roster.json`. Usernames and scrypt verifiers. The only half
that reaches the cluster.

**Seat** — one participant's environment: a pod with a CPU and memory
allocation and its own copy of `/data`.

**Verifier** — the one-way hash of a password. Enough to check a login, not
enough to recover the password.

## Tooling

**[bandit](https://bandit.readthedocs.io/en/latest/)** — a security linter for Python source.

**[checkov](https://www.checkov.io/)** — a security scanner for infrastructure code. Skips are justified
in `.checkov.yaml`.

**[gitleaks](https://github.com/gitleaks/gitleaks)** — scans commits for credentials that should not be there.

**[hadolint](https://github.com/hadolint/hadolint)** — a linter for Dockerfiles.

**[mypy](https://mypy.readthedocs.io/en/stable/)** — a static type checker. Run strict over `src/`.

**[pre-commit](https://pre-commit.com/)** — runs the tools above as git hooks. Installed by `make setup`.

**[pylint](https://pylint.readthedocs.io/en/stable/)** — an inference-based Python linter. Configured from Google's
published `.pylintrc`.

**[ruff](https://docs.astral.sh/ruff/)** — the formatter and first-line linter. Owns line length, import order,
quoting and docstring style.

## Cryptography

**[Constant-time comparison](https://docs.python.org/3/library/hmac.html)** — comparing without returning early, so timing
leaks nothing. `hmac.compare_digest`.

**[KDF](https://datatracker.ietf.org/doc/html/rfc7914)** — key derivation function. Turns a password into a hash, slowly and
deliberately.

**[Memory-hard](https://datatracker.ietf.org/doc/html/rfc7914)** — requiring significant memory per attempt, which is what makes
scrypt expensive to attack in parallel.

**[Salt](https://datatracker.ietf.org/doc/html/rfc7914)** — random bytes mixed into a hash so identical passwords produce
different verifiers, and precomputed tables are useless.

**[scrypt](https://docs.python.org/3/library/hashlib.html)** — the memory-hard KDF used here. In Python's standard library, which
is why the hub needs no extra dependency.
