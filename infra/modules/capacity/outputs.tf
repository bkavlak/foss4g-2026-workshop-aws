output "plan" {
  description = "The node group that will hold the requested seats."
  value = {
    instance_type  = local.instance_type
    nodes          = local.nodes
    seats_per_node = local.seats_per_node
    disk_gib       = local.disk_gib
  }

  precondition {
    condition     = local.fits
    error_message = "No supported instance type can host a seat of ${var.workload.vcpu} vCPU / ${var.workload.memory_gib} GiB."
  }

  precondition {
    condition     = local.nodes <= var.max_nodes
    error_message = "${var.workload.replicas} seats would need ${local.nodes} nodes, above the max_nodes limit of ${var.max_nodes}."
  }
}
