# Kubernetes and Helm, minimally

Enough to read `charts/workshop/` without guessing. This is not a [Kubernetes](https://kubernetes.io/docs/concepts/overview/)
course; it is the subset this repository uses.

## The idea

Kubernetes is a control loop over a database of desired state. You POST an
object saying "I want a pod running this image"; a controller notices reality
does not match and starts one. If the pod dies, reality stops matching again,
and it starts another.

That should feel familiar — it is the same declarative model as [OpenTofu](https://opentofu.org/docs/), one
layer down. OpenTofu reconciles AWS resources; Kubernetes reconciles containers.
This repository uses both because they are good at different things: OpenTofu
creates the cluster, Kubernetes keeps the seats alive inside it.

## The five object types you will meet

| Object | What it is | Where in this repo |
|---|---|---|
| **[Pod](https://kubernetes.io/docs/concepts/workloads/pods/)** | One or more containers scheduled together. The unit that runs. | One per participant, created by JupyterHub |
| **[Service](https://kubernetes.io/docs/concepts/services-networking/service/)** | A stable address in front of pods. `type: LoadBalancer` asks AWS for a real [load balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/userguide/what-is-load-balancing.html). | `proxy-public` — the URL you hand out |
| **[Secret](https://kubernetes.io/docs/concepts/configuration/secret/)** | Key–value data, base64-encoded, mounted as files or env vars | `templates/roster-secret.yaml` |
| **[ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/)** | The same, for things that are not sensitive | `templates/roster-authenticator.yaml` |
| **[ServiceAccount](https://kubernetes.io/docs/concepts/security/service-accounts/)** | An identity a pod runs as | `templates/participant-serviceaccount.yaml` |

**A Secret is not encrypted.** It is base64, which is an encoding, not a cipher.
It is "secret" only in the sense that access to it is controlled separately from
access to other objects. This is a common and expensive misunderstanding.

## What an init container is

A container in the pod that runs to completion *before* the main containers
start. If it fails, the pod restarts it. Ordinary containers in a pod all start
together; init containers are the exception.

This is exactly the guarantee the dataset needs:

```yaml
initContainers:
  - name: dataset-sync
    image: public.ecr.aws/aws-cli/aws-cli:2.22.35
    command: [aws, s3, sync, "s3://geo-workshop-data", /data, --only-show-errors]
```

JupyterLab cannot start until `aws s3 sync` exits successfully, so `/data` is
either complete or the seat has not appeared yet. There is no state where a
participant sees half a dataset. That is worth more than it sounds — "some of my
files are missing" is a terrible thing to debug live.

## Helm in three terms

- **[Chart](https://helm.sh/docs/topics/charts/)** — a directory of templated Kubernetes YAML plus a
  `values.yaml` of defaults. A package.
- **[Values](https://helm.sh/docs/chart_template_guide/values_files/)** — the parameters. Users override defaults; the chart
  interpolates them into the YAML.
- **[Release](https://helm.sh/docs/glossary/)** — an installed instance of a chart in a cluster,
  with a name.

[`helm template`](https://helm.sh/docs/helm/helm_template/) renders a chart to YAML locally and prints
it. It contacts
nothing. That is why `tests/test_chart.py` can assert on what this chart
produces without a cluster, and why you should run it whenever a template
confuses you:

```bash
helm template workshop charts/workshop --show-only templates/roster-secret.yaml
```

## Why this chart wraps another chart

`Chart.yaml` declares a dependency:

```yaml
dependencies:
  - name: jupyterhub
    version: "4.4.0"
    repository: https://hub.jupyter.org/helm-chart/
```

That version is not free to choose. Chart 4.4.0 ships [JupyterHub](https://jupyterhub.readthedocs.io/en/stable/) 5.5.0, and
`docker/requirements.txt` pins the participant image to the same 5.5.0. A
singleuser image whose `jupyterhub` major differs from the hub's fails to start
seats, so the two move together.

JupyterHub 5 also split *authentication* from *authorisation* and denies by
default. A custom authenticator that returns a username is no longer enough —
without `allow_all`, every participant would type a correct password, be
authenticated, and then be refused. `RosterAuthenticator` sets it, because the
roster already **is** the allowlist.

JupyterHub's official chart ("Zero to JupyterHub") is excellent and exposes
several hundred settings. A workshop maintainer should not have to hold any of
them in their head. So `charts/workshop/values.yaml` fixes all of them once, and
exposes four things that actually describe a workshop:

```yaml
image:     # the participant environment
dataset:   # where the data comes from, and who may read it
seat:      # what one participant may consume
roster:    # who may log in
```

That is the whole interface. The several hundred settings below it are wiring
that does not vary between workshops.

## The one genuinely awkward constraint

**A parent chart cannot template its subchart's values.** `values.yaml` is not
itself a template — [Helm](https://helm.sh/docs/) renders `templates/`, not `values.yaml`. So the parent
cannot write `singleuser.image.name: {{ .Values.image.repository }}`.

Three ways out, and why this repo took the third:

1. Set every dynamic leaf with `helm --set jupyterhub.singleuser.image.name=…`.
   Works, but the interface leaks: callers must know JupyterHub's paths.
2. Drop the wrapper and configure JupyterHub directly. Then nothing is hidden.
3. **Render the dynamic leaves from outside Helm.** OpenTofu's `templatefile()`
   produces `infra/modules/platform/values.yaml.tftpl`, which is the parent
   template Helm does not provide. The chart keeps the static wiring; the
   template supplies the per-workshop facts.

Objects the chart owns itself — the Secret, the ConfigMap, the ServiceAccount —
*are* templated normally, because those are its own templates. Only the
subchart's values need the workaround.

This is why `charts/workshop/templates/_helpers.tpl` uses fixed names like
`workshop-roster` rather than release-prefixed ones: JupyterHub's static values
must reference them by name, and a name it cannot compute must be a constant.
The cost is one workshop per namespace, which is a trade worth making.

## How a login actually works

1. Participant POSTs a username and password to the hub.
2. The hub runs `charts/workshop/files/roster_authenticator.py`, mounted from a
   ConfigMap, executed by the `hub.extraConfig` snippet in `values.yaml`.
3. It reads `/etc/workshop/roster.json` — the mounted Secret — and checks the
   password with `hashlib.scrypt`.
4. On success it returns the username, and JupyterHub spawns that participant's
   pod.
5. The pod's [init container](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/) syncs `/data`, then JupyterLab starts.

The roster is re-read on every login, so you can add a latecomer by patching the
Secret without restarting the hub and dropping everyone's session.

---

Next: [state, drift and blast radius](04-state-and-drift.md).
