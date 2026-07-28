# Everything a participant interacts with: the hub, their seats, their logins
# and their data.
#
# This module is where the workshop's vocabulary is translated into JupyterHub's
# once. The chart holds the wiring that never varies; the values template below
# holds the handful of facts that do. Callers supply four things and get a
# working, password-protected environment.

terraform {
  required_providers {
    helm = { source = "hashicorp/helm" }
  }
}

resource "helm_release" "workshop" {
  name             = var.release_name
  namespace        = var.namespace
  create_namespace = true
  chart            = "${path.module}/../../../charts/workshop"

  dependency_update = true

  # Pulling the participant image and the dataset takes minutes on a cold node;
  # failing the apply before that finishes would report a false problem.
  timeout = 1800
  wait    = true
  atomic  = true

  values = [templatefile("${path.module}/values.yaml.tftpl", {
    image       = var.image
    seat        = var.seat
    dataset     = var.dataset
    roster_json = jsonencode(var.roster)
    data_path   = "/data"
  })]
}
