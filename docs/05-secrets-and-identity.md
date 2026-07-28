# Secrets and identity

Two questions that look similar and are not. *Secrets*: how does a password get
from your laptop to the hub without being written somewhere it should not be?
*Identity*: how does a pod prove to AWS that it may read the dataset, without
holding a key at all?

## Part 1: the roster

### Where secrets leak in IaC

Before the design, the failure modes. A secret in an [OpenTofu](https://opentofu.org/docs/) project can end up
in:

1. **The state file.** Everything an apply knows is stored, in plaintext JSON.
   `sensitive = true` only redacts CLI *output* — it changes nothing about what
   is written to disk.
2. **Plan output.** Which people paste into chat when asking for help.
3. **Git history.** Committed once, present forever, even after deletion.
4. **CI logs.** Which are usually retained longer and read by more people than
   anyone assumes.
5. **A [Kubernetes](https://kubernetes.io/docs/concepts/overview/) Secret**, which is base64, not encryption.
6. **Shell history**, via `--set password=…`.

Any design that says "be careful" about six separate paths will fail on one of
them eventually.

### What this repository does instead

It arranges for the plaintext to not exist in any of those places, by never
sending it.

```
workshop provision
        │
        ├──▶ handout.csv    plaintext, mode 0600, your laptop only
        │                   never read by OpenTofu, never uploaded
        │
        └──▶ roster.json    scrypt verifiers only
                    │
                    ▼
              OpenTofu state ──▶ Kubernetes Secret ──▶ hub reads on login
```

A **verifier** is the output of a one-way function. You can check a password
against it; you cannot recover the password from it.

```json
{
  "user3": {
    "salt": "9f2c…", "hash": "c41a…",
    "n": 16384, "r": 8, "p": 1
  }
}
```

So the six leak paths still leak — but what leaks is a [scrypt](https://docs.python.org/3/library/hashlib.html) hash. An attacker
with the state file, the plan output, the git history and the Kubernetes Secret
has to brute-force twelve random characters at 16 MB of memory per guess, for
credentials that stop existing when you run `make down`.

The plaintext exists in exactly one place, on paper, in your hand.

### The design detail worth stealing

`Roster` **cannot represent a plaintext password.** Look at `src/workshop/roster.py`:
`provision()` mints, writes the handout, and returns an object holding only
verifiers. There is no field to read a password from.

This is the difference between a rule and a property. "Remember not to log the
passwords" is a rule, and rules are broken by the person who edits the file in
six months. "There is no password to log" is a property, and it holds without
anyone remembering it.

### Why scrypt, and why the parameters travel with the hash

Not SHA-256: it is fast, which is exactly wrong. ([scrypt is specified in
RFC 7914](https://datatracker.ietf.org/doc/html/rfc7914).) A password hash should be
*slow* and *memory-hard*, so that guessing is expensive. `n=16384, r=8` puts a
single check around 16 MB and well under 100 ms — invisible at login, ruinous at
scale.

Not bcrypt, for a specific reason: the verification half runs inside the
[JupyterHub](https://jupyterhub.readthedocs.io/en/stable/) image, which this project does not build or control. `hashlib.scrypt`
is standard library, so the authenticator adds no dependency to someone else's
image. Compare `charts/workshop/files/roster_authenticator.py` — its imports are
`hashlib`, `hmac`, `json`, `os`.

The cost parameters are stored *inside* each verifier rather than as a constant
in the checking code. That is what lets you raise the cost later without
invalidating rosters minted under the old policy.

And [`hmac.compare_digest`](https://docs.python.org/3/library/hmac.html), not `==`: comparing byte by
byte and returning early
leaks, through timing, how much of the hash was correct. Rarely exploitable,
free to avoid.

### The duplication, and why it is safe

The scrypt policy exists twice: `src/workshop/credentials.py` mints,
`charts/workshop/files/roster_authenticator.py` verifies. Two copies of one
decision is normally a design smell.

It is load-bearing here — the hub cannot import this project's package — so the
mitigation is a test that mints with one and verifies with the other:

```python
def test_hub_side_verification_accepts_this_project_s_credentials(
    authenticator,
):
    credential = credentials.mint()
    assert authenticator.verify(credential.verifier, credential.password)
```

Change the parameters on one side and the suite fails. The duplication cannot
drift silently, which is the only thing that made it dangerous.

## Part 2: IRSA, or how a pod proves who it is

### The problem

The [init container](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/) runs `aws s3 sync s3://geo-workshop-data /data`. To read that
bucket it needs AWS credentials. Where do they come from?

The obvious answers are all bad:

- **Access keys in the image.** Now the credentials are in every layer, in [ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html),
  in anyone's `docker pull`, and they do not expire.
- **Access keys in a Kubernetes Secret.** Better, still long-lived, still
  base64, still in state.
- **Permissions on the node's instance role.** Works — and grants the same
  access to *every* pod on that node, including the participant containers
  running arbitrary code that people type into a notebook.

That last one is worth dwelling on, because it is the common shortcut. Your
participants can run any Python they like. If the node role can read S3, so can
they, with no barrier at all.

### What IRSA does

**[IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction.html) Roles for Service Accounts.** The chain:

1. The cluster runs an OIDC identity provider. `modules/cluster` enables it with
   `enable_irsa = true`, and AWS is told to trust it.
2. A pod using the `workshop-participant` [ServiceAccount](https://kubernetes.io/docs/concepts/security/service-accounts/) gets a short-lived,
   signed JWT projected into its filesystem. The token says: *this pod is
   `system:serviceaccount:workshop:workshop-participant` in this cluster*.
3. The AWS SDK finds that token and calls `sts:AssumeRoleWithWebIdentity`.
4. [STS](https://docs.aws.amazon.com/STS/latest/APIReference/welcome.html) checks the signature against the cluster's [OIDC provider](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_oidc.html), checks the
   claims against the role's trust policy, and returns temporary credentials
   that expire in an hour.

No key is ever stored. Nothing has to be rotated. Nothing survives the pod.

### The line that does the work

From `infra/modules/dataset/main.tf`:

```hcl
Condition = {
  StringEquals = {
    "${var.reader.oidc_issuer_host}:sub" = "system:serviceaccount:workshop:workshop-participant"
    "${var.reader.oidc_issuer_host}:aud" = "sts.amazonaws.com"
  }
}
```

The `sub` condition is the whole security boundary. Without it, *any* pod in the
cluster presenting *any* service account token could assume this role. With it,
only pods running as that one account can — and the participant's notebook
container runs as that account too, which is fine, because the role grants
`s3:GetObject` and `s3:ListBucket` and nothing else.

The `aud` condition stops a token minted for a different audience being replayed
here.

Both are covered by `infra/tests/dataset.tftest.hcl`, which asserts the trust
policy contains that exact service account string and that the permission policy
contains no `Put` or `Delete`. Those run with no AWS account.

### Least privilege, concretely

The role can read one bucket. It cannot write to it — so a participant cannot
corrupt the shared dataset for everyone else, deliberately or by typing
`gdal.Translate` at the wrong path. It cannot read any other bucket. It cannot
do anything that is not S3.

Ask of any permission: *what is the worst thing the holder can do?* Here, the
answer is "read data we deliberately gave them", which is the answer you want.

## Part 3: your own credentials

The two parts above are about identities this repository creates. There is a
third: yours, the one that runs `tofu apply`.

It is the most powerful credential in the story — it can create and destroy
everything — and it is the one this repository deliberately knows nothing
about. `.env` records a *profile name*; the credential itself lives in
`~/.aws/`, managed by the AWS CLI, outside the repository and outside git. That
is why `gitleaks` runs on every commit and why there is no `AWS_SECRET_ACCESS_KEY`
anywhere in this tree: the design is that there is nothing here to leak.

**Prefer IAM Identity Center over IAM user access keys.** Identity Center issues
short-lived credentials that expire on their own. An access key is a permanent
secret that stays valid until someone remembers to rotate it, which is the same
problem [IRSA](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
solves for pods — and the reasoning is identical at both scales. If a key is the
only option available to you, know that you have accepted a long-lived secret
and treat it that way.

The setup steps are in the [repository README](../README.md#connecting-your-aws-account).

---

Next: [testing and confidence](06-testing.md).
