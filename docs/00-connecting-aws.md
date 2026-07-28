# Connecting your AWS account

Assumes you have never done this before. If you already have a working
`aws` profile, skip to [checking it works](#4-check-it-worked).

## Before anything else: the tools

This repository does not bundle the AWS CLI, OpenTofu, kubectl or Helm. It
*pins* them in `.tool-versions` and installs them with
[asdf](https://asdf-vm.com/), a version manager.

```bash
brew install asdf          # macOS; otherwise see the asdf guide
# add asdf to your shell as its docs describe, then open a new terminal
make setup                 # installs every pinned tool. Python is built from
                           # source, so allow a few minutes.
make doctor                # reports anything still missing, and how to get it
```

Docker is the one tool asdf does not install; get it from
[Docker Desktop](https://docs.docker.com/get-started/get-docker/).

If `make up` ever fails with `tofu: No such file or directory`, the toolchain
is not installed. Run `make doctor`.

## What we are actually doing

Everything in this repository — OpenTofu, the AWS CLI, kubectl — needs to prove
to AWS that it is allowed to create things in your account. That proof is a
**credential**.

The credential does **not** go in this repository. It goes in a file called
`~/.aws/config` (and sometimes `~/.aws/credentials`) that the AWS CLI creates
and manages for you. This repository's `.env` records only the *name* you gave
it. That is why you will never see an access key anywhere in this project, and
why `gitleaks` runs on every commit to make sure it stays that way.

A named credential is called a **profile**. We will call ours `workshop`.

## The words you will meet

You do not need to understand AWS's identity system to run a workshop, but five
words appear in every screen and you will be lost without them:

| Word | What it means |
|---|---|
| **Root user** | The email address and password you signed up to AWS with. It can do *anything*, including close the account. You use it to set up other logins, and then you stop using it. **Never create access keys for it.** |
| **IAM user** | A login you create inside your account for a person or a script. It can hold **access keys** — a username/password pair for programs — which never expire until you delete them. |
| **IAM Identity Center** | AWS's newer, recommended way to log in. Confusingly it used to be called **AWS SSO**, and the AWS CLI still calls it `sso` in commands. Instead of a permanent key, you log in through a browser and receive a credential that expires by itself. |
| **Access key** | Two strings: an ID that looks like `AKIAIOSFODNN7EXAMPLE` and a secret that looks like `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`. Anyone holding both is you, until you revoke them. |
| **Region** | Which physical part of the world your resources live in, e.g. `eu-central-1` (Frankfurt). |

**SSO** stands for "single sign-on" — logging in once and getting access to
several things. That is all it means. Do not let the acronym put you off.

## Which situation are you in?

**A. Someone at your organisation gave you a link** that looks like
`https://something.awsapps.com/start`, and you log in to AWS through it.
→ You already have Identity Center. Go to [path A](#path-a-your-organisation-already-has-a-login-portal).
It is four questions and you are done.

**B. You signed up for AWS yourself** with your own email and card, and you log
in at `aws.amazon.com` with that email.
→ You have a root user and nothing else yet. Go to [path B](#path-b-its-your-own-account).

---

## Path A: your organisation already has a login portal

You need two things from whoever gave you the link, or from the portal page
itself:

- the **start URL** — the `https://something.awsapps.com/start` link
- the **SSO region** — the region Identity Center runs in. It is *not*
  necessarily where your workshop will run. Ask, or look at the portal page,
  which usually shows it.

Then:

```bash
aws configure sso
```

It asks four questions before opening your browser. Here is the whole exchange,
with what to type:

```
SSO session name (Recommended): workshop
```
> Any name you like. It labels this login on your own machine. `workshop` is fine.

```
SSO start URL [None]: https://something.awsapps.com/start
```
> Paste the link. Include `https://`.

```
SSO region [None]: us-east-1
```
> The region Identity Center runs in — the one you asked for above.

```
SSO registration scopes [sso:account:access]:
```
> **Press Enter.** The default is correct. This is asking what the login is
> allowed to do, and the default means "list and access accounts".

Your browser now opens and asks you to confirm. Approve it, return to the
terminal, and it continues:

```
There are 2 AWS accounts available to you.
> Workshop Account (123456789012)
```
> Arrow keys to choose, Enter to confirm. If there is only one, it picks it.

```
There are 2 roles available to you.
> AdministratorAccess
```
> Choose the most permissive role you are offered. See
> [permissions](#permissions) for why.

```
CLI default client Region [None]: eu-central-1
```
> **This one is different.** This is where *your workshop* will be built, not
> where Identity Center lives. Use the same value you will put in `.env` as
> `AWS_REGION`.

```
CLI default output format [None]: json
```
> Type `json`.

```
CLI profile name [AdministratorAccess-123456789012]: workshop
```
> Type `workshop`. This is the name `.env` will refer to.

**Later, when it stops working:** Identity Center credentials expire, usually
after a few hours or at the end of the day. That is the point of them. When AWS
starts refusing you, run:

```bash
aws sso login --profile workshop
```

Browser opens, you approve, you are back. Nothing is reconfigured.

---

## Path B: it's your own account

You have two options. They differ in about ten minutes of setup and in how
dangerous a mistake is later.

### B1. The short path: an IAM user with access keys

Fewer steps. What you accept is a **permanent secret on your laptop** — a key
that works forever until you delete it. If it leaks, someone else can run up
charges on your card. For a single workshop on a personal account, many people
take this path knowingly.

1. Sign in at `aws.amazon.com` with your root email and password.
2. In the search bar at the top, type **IAM** and open it.
3. Left sidebar → **Users** → **Create user**.
4. **User name**: `workshop-admin`. Leave "Provide user access to the AWS
   Management Console" **unchecked** — this login is only for the command line.
   **Next**.
5. **Set permissions** → choose **Attach policies directly** → tick
   **AdministratorAccess** → **Next** → **Create user**.
6. Click the user you just made → **Security credentials** tab → **Create
   access key**.
7. Use case: **Command Line Interface (CLI)**. Tick the confirmation box at the
   bottom → **Next** → **Create access key**.
8. You now see the **Access key** and the **Secret access key**. The secret is
   shown **once**. Leave this page open until the next step is done.

Then, in a terminal:

```bash
aws configure --profile workshop
```

```
AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
```
> Paste the access key from step 8.

```
AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```
> Paste the secret. **Nothing appears as you type or paste** — no dots, no
> stars. That is normal. Paste once and press Enter.

```
Default region name [None]: eu-central-1
```
> Where your workshop will run. The same value you will put in `.env`.

```
Default output format [None]: json
```
> Type `json`.

**When the workshop is over, delete the key.** IAM → Users → `workshop-admin`
→ Security credentials → the key → **Actions** → **Delete**. A key you are not
using is a key that can only hurt you.

### B2. The longer path: set up Identity Center yourself

About ten minutes of clicking, once. Afterwards you are in
[path A](#path-a-your-organisation-already-has-a-login-portal) forever, and no
permanent secret ever exists on your laptop.

1. Sign in as root. Search for **IAM Identity Center** → **Enable**.
2. Pick a region when asked. Note it down — this is your **SSO region**.
3. The dashboard now shows an **AWS access portal URL** like
   `https://d-1234567890.awsapps.com/start`. Note it down — this is your
   **start URL**.
4. **Users** → **Add user**. Your name and email. Finish the wizard.
5. **Permission sets** → **Create permission set** → **Predefined permission
   set** → **AdministratorAccess** → accept the defaults.
6. **AWS accounts** → tick your account → **Assign users or groups** → pick
   your user → pick the `AdministratorAccess` permission set → submit.
7. Check your email, accept the invitation, set a password, and set up MFA when
   it asks. Do set up MFA.
8. Now follow [path A](#path-a-your-organisation-already-has-a-login-portal)
   with the URL and region from steps 2 and 3.

---

## 3. Tell the repository which profile to use

```bash
cp .env.example .env
```

Open `.env` and set two values:

```
AWS_PROFILE=workshop
AWS_REGION=eu-central-1
```

`AWS_PROFILE` is the name you chose at the last prompt. `AWS_REGION` drives
both the AWS CLI and OpenTofu, so change it in this one place and everything
follows.

## 4. Check it worked

```bash
aws sts get-caller-identity --profile workshop
```

Success looks like this:

```json
{
    "UserId": "AIDAEXAMPLEEXAMPLE",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/workshop-admin"
}
```

Three fields, one of them your twelve-digit account number. **That is the whole
test.** If it works, you are connected.

### If it does not

| Message | What it means |
|---|---|
| `The config profile (workshop) could not be found` | The profile name here and the one you typed at the last prompt do not match. Run `aws configure list-profiles` to see what exists. |
| `The security token included in the request is invalid` | Access keys are wrong — most often the secret was pasted with a stray space or newline. Run `aws configure --profile workshop` again. |
| `Error loading SSO Token` or `session associated with this profile has expired` | Normal for Identity Center. Run `aws sso login --profile workshop`. |
| `command not found: aws` | The CLI is not installed. `make setup` installs it via [asdf](https://asdf-vm.com/), or install it from [AWS's instructions](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html). |

## Permissions

Bringing this workshop up creates a
[VPC](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html),
an [EKS](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html)
cluster, node groups,
[IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction.html) roles,
an OIDC provider, a KMS key, an
[S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html) bucket
and an [ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html)
repository.

You have three options, in order of increasing effort.

### 1. AdministratorAccess

One AWS-managed policy, nothing to maintain, and it will never be the reason an
apply fails. This is what the steps above attach, and on a personal account it
is the right answer. `AdministratorAccess` is offered in the console's policy
list — search for it and tick it.

### 2. PowerUserAccess + IAMFullAccess

Two AWS-managed policies. `PowerUserAccess` covers every service but not IAM;
`IAMFullAccess` adds the role and OIDC-provider creation this stack needs.

Worth knowing before you choose it for security reasons: anyone with
`IAMFullAccess` can create a new administrator and become one. What this pair
genuinely blocks is account-level damage — closing the account, changing
billing, touching AWS Organizations — not privilege escalation.

### 3. A scoped policy

If an administrator needs to see exactly what this stack touches, hand them
[`workshop-provisioner-policy.json`](iam/workshop-provisioner-policy.json). It
is derived from the resource types the configuration and its two community
modules actually declare, in nine statements:

| Statement | Why it is needed |
|---|---|
| `ReadOnlyDiscovery` | OpenTofu re-reads every resource on each plan. Most of this policy's length is reads, not writes. |
| `Networking` | The VPC, subnets, route tables, NAT gateway, elastic IP and security groups |
| `NodeLaunchTemplates` | Managed node groups are created from a launch template |
| `Cluster` | The EKS cluster, node group, addons, and the access entry that makes you an admin of your own cluster |
| `IdentityForClusterAndPods` | Roles for the cluster and nodes, and the OIDC provider that makes IRSA work |
| `ClusterSecretsEncryption` | The KMS key EKS uses to encrypt Kubernetes secrets |
| `ControlPlaneLogs` | The CloudWatch log group for control-plane logs, scoped to `/aws/eks/*` |
| `ParticipantImageRegistry` | Creating the ECR repository and pushing the participant image |
| `DatasetBucket` | Creating the dataset bucket and running `make data-push` |

To attach it: **IAM** → **Policies** → **Create policy** → **JSON** tab →
paste the file → name it `workshop-provisioner` → then **Users** →
`workshop-admin` → **Add permissions** → **Attach policies directly**.

Two things to know:

- **A managed policy is limited to 6,144 characters.** This one is about 4,700
  once AWS strips the whitespace, so pasting the readable version is fine. A
  test in this repository fails if it grows past the limit.
- **`make down` needs the same permissions as `make up`.** Do not attach this
  for the apply and remove it afterwards, or you will not be able to tear the
  workshop down — and a stack you cannot destroy keeps billing.

### The honest caveat

A least-privilege policy for provisioning EKS is genuine work to get right, and
the failure mode is unpleasant: a policy that is *almost* right fails halfway
through a `tofu apply`, leaving half-built resources that still cost money and
must be cleaned up by hand.

If you take option 3, prove it before you rely on it:

```bash
make plan
```

A plan exercises nearly all the read permissions and none of the writes. If it
completes, the discovery half of the policy is right. The write half you only
learn about during an apply — so do it on a rehearsal with
`PARTICIPANTS=2`, not on the morning.

## Before you spend anything

**Set a budget alert first.** Search for **Budgets** in the console, create one
for $50, and have it email you at 80%. It takes five minutes and turns "found
out six weeks later" into "found out on day two".

Then, still spending nothing:

```bash
make check          # every offline test; touches no cloud
make plan           # first command that talks to AWS; changes nothing
```

Read the last line of the plan. `Plan: N to add, 0 to change, 0 to destroy.`

When you are ready, [running a workshop](../README.md#running-a-workshop)
takes over.

---

Next: [what Infrastructure as Code actually is](01-what-iac-is.md).
