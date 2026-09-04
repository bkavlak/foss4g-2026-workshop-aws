
> [!NOTE]
> VIBEEEECODED.

# Workshop environment

A browser-accessible GDAL + Python environment, one seat per participant,
protected by individual usernames and passwords. The maintainer starts it
before the workshop and destroys it afterwards; participants need nothing but
a browser and a row from a printed handout.

## Shape of the system

```
  workshop provision  ──▶  roster/roster.json  ──┐
                           roster/handout.csv     │  (paper, never leaves your laptop)
                                                  ▼
  docker/  ──▶  ECR  ──┐                    OpenTofu
  data/    ──▶  S3   ──┴──────────────────▶  ├─ network   VPC, subnets, NAT
                                             ├─ registry  ECR + retention
                                             ├─ cluster   EKS sized from headcount
                                             ├─ dataset   S3 bucket + IRSA read grant
                                             └─ platform  Helm release
                                                            │
                                                            ▼
                                              charts/workshop  (JupyterHub)
                                                            │
                                                            ▼
                                               http://<load-balancer>/
```

Each OpenTofu module owns one decision and states its interface in the
workshop's vocabulary, not AWS's. `modules/cluster`, for example, is asked for
*"5 seats of 1 vCPU and 4 GiB"* and answers with a cluster; instance families,
spot configuration, node counts, disk sizing and IRSA are its business alone.

## Connecting your AWS account

Nothing in this repository stores a credential. OpenTofu, the AWS CLI and
kubectl all authenticate through a named profile that the AWS CLI keeps in
`~/.aws/`; `.env` records only which profile to use.

**Never set this up before? Read
[docs/00-connecting-aws.md](docs/00-connecting-aws.md).** It assumes no prior
knowledge, explains what SSO and access keys actually are, and walks through
every prompt with the value to type.

The short version, if you have done it before:

```bash
aws configure sso --profile workshop   # IAM Identity Center (preferred), or
aws configure --profile workshop       # IAM user access keys

cp .env.example .env                   # AWS_PROFILE=workshop, AWS_REGION=...
aws sts get-caller-identity --profile workshop
```

If that last command prints an account ID and an ARN, you are connected.
`AWS_REGION` drives both the AWS CLI and OpenTofu's `var.region`, so set it in
that one place.

Bringing the workshop up needs broad permissions — VPC, EKS, IAM roles, an OIDC
provider, KMS, S3, ECR. On a personal account `AdministratorAccess` is the
pragmatic answer; on a shared account, ask an administrator rather than
guessing.

**Set a budget alert before your first `make up`.** $50, email at 80%, five
minutes.

After `make up`, point kubectl at the cluster:

```bash
aws eks update-kubeconfig --name geo-workshop --region eu-central-1
kubectl config set-context --current --namespace=workshop
```

Do that the evening before, not on the morning.

## Running a workshop

**Prerequisites.** This repository pins every tool it uses in `.tool-versions`
and installs them with [asdf](https://asdf-vm.com/). Install asdf first —
`brew install asdf` on macOS, otherwise the
[asdf guide](https://asdf-vm.com/guide/getting-started.html) — and add it to
your shell as its docs describe. Docker is the one thing asdf does not install;
get it from [Docker Desktop](https://docs.docker.com/get-started/get-docker/).

At any point, `make doctor` reports exactly which tools are missing and how to
get each one.

```bash
make setup                      # asdf plugins + pinned versions + uv env + hooks
cp .env.example .env            # AWS profile, region, headcount
make check                      # every offline test; no AWS account needed

make roster PARTICIPANTS=5      # mint logins → roster/{roster.json,handout.csv}
make up PARTICIPANTS=5          # provision, push image and data, deploy
make url                        # the address to project on screen
```

Hand each participant one line of `roster/handout.csv`.

Afterwards:

```bash
make down
```

### What `make up` does, and why it is staged

The image must exist in ECR before Kubernetes can pull it, and the dataset must
exist in S3 before a seat can sync it — but both live in resources OpenTofu
itself creates. `make up` therefore applies the registry and bucket first,
pushes into them, then applies the rest. This is orchestration, so it lives in
the Makefile rather than being smuggled into a module.

## The dataset

`data/` is expected to hold roughly 20 GB. It is **not** baked into the image:
a 20 GB image takes minutes to push and pull, and would have to be rebuilt
whenever the data changed. Instead `make data-push` mirrors it into S3, and an
init container syncs it into each seat's `/data` before JupyterLab starts, so
a participant never sees a half-populated directory.

Node disks are sized to hold one copy per seat on the node — `make plan` prints
the resulting `capacity_plan`. If per-seat copies become the dominant cost,
`modules/platform` is where a shared EFS mount would replace the init container,
and no other module would change.

Leave `data/` empty and the init container is omitted entirely.

## Credentials

`workshop provision` mints one password per participant and writes two files.
Only the scrypt verifiers travel to the cluster; the plaintext exists in
`handout.csv` (mode 0600) and nowhere else — not in OpenTofu state, not in a
Secret, not in the hub's database. Should a handout leak, re-run `make roster`
and `make up`: every previously issued password stops working.

Logins are checked by `charts/workshop/files/roster_authenticator.py`, which
runs inside the hub. It uses only the standard library, so it adds no
dependency to an image we do not control. The suite mints with
`workshop.credentials` and verifies with that file, which is what stops the two
halves of the policy drifting apart.

## Learning what this is

`docs/` explains the infrastructure side for someone comfortable with Python and
GDAL but new to IaC: the mental model, a tour of every module, and the concerns
worth understanding before you spend money — state and drift, secrets and
identity, testing, and cost. It also contains a
[runbook](docs/08-runbook.md) for the workshop itself. Start at
[docs/README.md](docs/README.md).

## Testing

Everything runs locally and for free.

| Command | Covers |
|---|---|
| `make lint` | ruff (Google style, 80 cols), pylint, `helm lint`, `tofu fmt`, `tofu validate` |
| `make typecheck` | mypy, strict over `src/` |
| `make security` | bandit (Python), checkov (infrastructure) |
| `make test` | credential policy, roster provisioning, the hub-side authenticator, `helm template` output, and the documentation's links |
| `make test-infra` | `tofu test` — capacity packing as pure computation, plus IAM and registry policy against `mock_provider "aws"` |
| `make check` | all of the above |

No test contacts AWS or a Kubernetes API. `mock_provider` means `tofu test`
needs no credentials at all.

`make setup` installs the git hooks, so the same tools run on commit
(`.pre-commit-config.yaml`). Checkov runs on push rather than on commit because
it is slow; its skipped checks are justified individually in `.checkov.yaml`.

Python style follows the [Google Python Style
Guide](https://google.github.io/styleguide/pyguide.html). `.pylintrc` is
Google's published file with three marked deviations, and ruff is configured to
the same 80-column limit and Google docstring convention so the two cannot
disagree.

## Cost

There is no free tier for EKS. Expect roughly:

| | |
|---|---|
| EKS control plane | ~$0.10 / hour, unavoidable |
| Nodes | spot, ~70% off on-demand; `make plan` prints the count |
| NAT gateway | ~$0.045 / hour plus data |
| Load balancer | ~$0.025 / hour |
| S3 + ECR | cents for a 20 GB dataset over a few days |

A one-day workshop for 5 people lands under $10 **provided `make down` runs the
same day**. Left running, the same stack is a couple of hundred dollars a month. Nothing here is left running to be discovered
on next month's bill.

## Known trade-offs

- **HTTP, not HTTPS.** Passwords cross the wire in the clear. Acceptable on a
  workshop LAN for throwaway accounts; for anything else, point a domain at the
  load balancer and enable JupyterHub's `proxy.https` in
  `charts/workshop/values.yaml`.
- **Ephemeral home directories.** A seat is disposable. Participants export
  anything they want to keep before they leave.
- **One workshop per namespace.** The chart uses fixed resource names because
  JupyterHub is a subchart and subchart values cannot be templated.
- **Verifiers are in OpenTofu state.** Treat the state file as sensitive, or
  put it in an encrypted S3 backend.
