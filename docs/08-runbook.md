# Runbook: when it breaks live

Keep this open during the workshop. Symptom → diagnosis → command.

## Before anything else

```bash
export AWS_REGION=eu-central-1
aws eks update-kubeconfig --name geo-workshop --region $AWS_REGION
kubectl config set-context --current --namespace=workshop
```

Do this the evening before, not on the morning. If `kubectl get pods` works,
you are ready.

## The three [kubectl](https://kubernetes.io/docs/reference/kubectl/) commands that answer most questions

```bash
kubectl get pods                      # what is running, and in what state
kubectl describe pod <name>           # why it is in that state — read Events at the bottom
kubectl logs <name> -c <container>    # what it said before it died
```

For a participant seat the pod is named after their username, e.g.
`jupyter-user3`.

---

## Nobody can reach the URL

### The load balancer has no address yet

```bash
kubectl get svc proxy-public
```

`EXTERNAL-IP` showing `<pending>` for more than five minutes is not normal.

```bash
kubectl describe svc proxy-public     # Events explain the refusal
```

Usual causes: public subnets missing the `kubernetes.io/role/elb` tag (this
repository sets it in `modules/network`, so suspect this only if you have edited
that module), or an account-level load balancer quota.

### It has an address and still does not answer

DNS for a fresh AWS load balancer name can take a few minutes to propagate, and
the target group needs to pass health checks. Give it five minutes, then:

```bash
kubectl get pods -l component=proxy
kubectl get pods -l component=hub
```

Both must be `Running`. If the hub is not, see below.

**Have the URL on a slide before people arrive.** Get it the evening before with
`make url` — the address does not change once created.

---

## A participant cannot log in

### Everyone is affected

The hub cannot read the roster.

```bash
kubectl logs -l component=hub --tail=50
```

Look for `workshop roster is missing or unreadable`. Then confirm the Secret is
there and populated:

```bash
kubectl get secret workshop-roster -o jsonpath='{.data.roster\.json}' \
  | base64 -d | python3 -m json.tool | head
```

If it is missing or empty, `roster/roster.json` was probably absent or stale
when you ran `make up`. Fix and re-apply:

```bash
make roster PARTICIPANTS=5
make up PARTICIPANTS=5
```

**This invalidates every password already handed out.** If people are already
logged in, prefer patching the Secret (below) over re-provisioning.

### One person is affected

Almost always typing. The password excludes `l`, `1`, `I`, `O` and `0`
specifically to reduce this.

At this headcount the usernames are `user1` to `user5`, unpadded. Above nine
participants they gain a leading zero — `user07`, not `user7` — because the
width follows the headcount, and that is what catches people.

Usernames are case- and whitespace-insensitive; passwords are neither. Have them
type it into a text field where they can see it before pasting.

To confirm a credential is genuinely valid, check it locally against the same
roster the hub has — this needs no cluster:

```bash
python3 -c "
import sys; sys.path.insert(0, 'src')
from workshop.roster import Roster
print(Roster.load('roster').authenticates('user3', 'PASTE_PASSWORD'))
"
```

`True` means the credential is fine and the problem is elsewhere. `False` means
they are mistyping, or holding a handout from a previous `make roster`.

### Someone arrived who is not on the roster

The hub re-reads the roster on every login, so you can add a person without
restarting anything and without disturbing existing sessions.

```bash
# 1. Mint a larger roster locally (this rewrites handout.csv — keep the old one)
cp roster/handout.csv roster/handout-original.csv
make roster PARTICIPANTS=8

# 2. Push just the Secret
kubectl create secret generic workshop-roster \
  --from-file=roster.json=roster/roster.json \
  --dry-run=client -o yaml | kubectl apply -f -
```

**Everyone's password changes**, because `provision` mints fresh credentials for
all accounts. Re-hand the new `handout.csv`. If people are mid-session, they stay
logged in — the roster is only consulted at login — but they will need the new
password if they are logged out.

Cleaner if you expect stragglers: **provision more accounts than you need**.
Eight accounts for five people costs nothing — the cluster is sized from
`participant_count`, not from the roster, so spare logins are free.

---

## A seat will not start

```bash
kubectl get pods
kubectl describe pod jupyter-user3
```

Read the `Events` section at the bottom. It almost always says exactly what is
wrong. The state names below are from the
[pod lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/); `ImagePullBackOff` is explained under
[container images](https://kubernetes.io/docs/concepts/containers/images/).

### `Pending`

No node can take the pod.

```bash
kubectl get nodes
kubectl describe pod jupyter-user3 | grep -A5 Events
```

- *"Insufficient cpu/memory"* — the cluster is full. More people turned up than
  `PARTICIPANTS` allowed for, or seats are being held by people who left. The
  culler reclaims idle seats after an hour; to free one now:
  `kubectl delete pod jupyter-userNN`.
- *"had volume node affinity conflict"* or no nodes listed — spot capacity was
  reclaimed and nothing has replaced it. Check the node group in the console.
  Fastest fix under time pressure is to switch `capacity_type` to `"ON_DEMAND"`
  in `modules/cluster/main.tf` and `tofu -chdir=infra apply`, accepting the
  cost.

### `Init:0/1` for a long time

The dataset is still syncing. Expected on a cold node with 20 GB — several
minutes. Watch it:

```bash
kubectl logs jupyter-user3 -c dataset-sync --follow
```

If it is erroring rather than slow:

- `AccessDenied` — the [IRSA](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html) chain is broken. Check the annotation survived:
  ```bash
  kubectl get sa workshop-participant -o jsonpath='{.metadata.annotations}'
  ```
  It must show `eks.amazonaws.com/role-arn`. If empty, `dataset.uri` was blank
  at deploy time, so the chart omitted it.
- `NoSuchBucket` — `make data-push` was never run, or ran against a different
  workshop name.

### `ImagePullBackOff`

The node cannot pull the participant image.

```bash
kubectl describe pod jupyter-user3 | grep -A3 Failed
```

Usually the image was never pushed, or `IMAGE_TAG` differs between what you
pushed and what you deployed. Confirm what is in [ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html):

```bash
aws ecr describe-images --repository-name geo-workshop --region $AWS_REGION \
  --query 'imageDetails[].imageTags'
```

**ECR tags are immutable here.** If you need to rebuild the image, push it under
a new tag and deploy that — do not try to republish the old one:

```bash
make up IMAGE_TAG=v2
```

Republishing a tag would leave nodes that already cached it serving the old
layers, so some participants would get the fix and others would not. `make
image-push` refuses rather than let that happen.

### `CrashLoopBackOff`

The container starts and dies.

```bash
kubectl logs jupyter-user3 --previous
```

`--previous` is the important flag — without it you get the logs of the attempt
that has not failed yet.

---

## Everything is slow at 09:00

Five people logging in simultaneously means five pods scheduling and five
`aws s3 sync` runs at once. On a cold cluster this is slower than you expect,
and at 20 GB a seat it is the most likely thing to go wrong on the day.

**Prevent it.** Bring the cluster up at least an hour before, and log in as two
or three accounts yourself. That pulls the image onto every node and warms the
path. The seats you started will be culled after an hour of idleness, but the
image layers stay cached on the nodes.

If it is already happening: it will resolve, it just takes minutes. Give people
the tour of the notebook interface while it settles.

---

## A participant broke their environment

Delete the pod. [JupyterHub](https://jupyterhub.readthedocs.io/en/stable/) makes a new one, `/data` re-syncs, home directory
starts clean.

```bash
kubectl delete pod jupyter-user3
```

Home directories are ephemeral by design, so **anything they had not exported is
gone**. Say this at the start of the session, not at this moment.

---

## `make down` fails part-way

Common, and it matters — a partial destroy leaves things billing.

The usual cause: [Kubernetes](https://kubernetes.io/docs/concepts/overview/) created a load balancer that [OpenTofu](https://opentofu.org/docs/) does not know
about, and the [VPC](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html) will not delete while it exists. Remove the Kubernetes
objects first, then destroy:

```bash
kubectl delete svc proxy-public
sleep 60                              # let AWS actually remove the load balancer
make down
```

Then verify, rather than assuming:

```bash
tofu -chdir=infra state list          # should print nothing
aws eks list-clusters --region $AWS_REGION
aws ec2 describe-nat-gateways --region $AWS_REGION \
  --filter Name=state,Values=available
```

Anything left, delete in the console. A [NAT gateway](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html) or an [EKS](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html) cluster you forgot
is the expensive kind of leftover.

---

## The evening-before checklist

- [ ] `make check` passes
- [ ] `make roster` run, with **more accounts than attendees**
- [ ] `handout.csv` printed or ready to distribute
- [ ] `make up` completed
- [ ] `make url` prints an address, and that address loads in a browser
- [ ] You logged in as `user1` and opened a notebook
- [ ] `import gdal` works, and `/data` has the files in it
- [ ] `kubectl` is configured and `kubectl get pods` works
- [ ] The URL is on a slide
- [ ] A calendar reminder for `make down`, same day

---

Back to the [index](README.md), or the [glossary](glossary.md).
