# Workshop dataset

Put the read-only dataset that participants need here (expected ~20 GB).

The contents are **not** committed and **not** baked into the container image.
`make data-push` mirrors this directory into the workshop S3 bucket; each
participant pod then syncs it into `/data` with an init container before
JupyterLab starts.

Leave the directory empty to run the workshop without a dataset — the init
container is omitted entirely when no bucket URI is configured.
