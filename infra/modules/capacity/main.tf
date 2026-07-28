# Turns a seat description into a node group specification.
#
# Pure computation: no providers, no resources, no cloud calls. That is what
# lets `tofu test` exercise the packing rules directly, and it keeps the
# instance catalogue out of the cluster module where it would be tangled up
# with IAM and networking.

locals {
  # General-purpose instances only. Workshop seats are memory- and IO-bound
  # rather than compute-bound, and one family keeps spot capacity easy to find
  # across availability zones.
  catalog = {
    "m6i.large"   = { vcpu = 2, memory_gib = 8 }
    "m6i.xlarge"  = { vcpu = 4, memory_gib = 16 }
    "m6i.2xlarge" = { vcpu = 8, memory_gib = 32 }
    "m6i.4xlarge" = { vcpu = 16, memory_gib = 64 }
    "m6i.8xlarge" = { vcpu = 32, memory_gib = 128 }
  }

  # kubelet, the container runtime, the CNI and DaemonSets are not free. Only
  # this fraction of an instance is schedulable by participant pods.
  schedulable = 0.85

  candidates = {
    for name, size in local.catalog :
    name => {
      seats_per_node = min(
        floor(size.vcpu * local.schedulable / var.workload.vcpu),
        floor(size.memory_gib * local.schedulable / var.workload.memory_gib),
      )
      vcpu = size.vcpu
    }
    if size.vcpu * local.schedulable >= var.workload.vcpu
    && size.memory_gib * local.schedulable >= var.workload.memory_gib
  }

  # Rank by how much hardware is actually bought, not by instance size. Picking
  # the smallest machine that fits one seat looks frugal and is not: an
  # instance that holds a single seat wastes the whole per-node overhead, so a
  # 25-person workshop would be billed for 25 machines.
  #
  # Ties go to the smaller instance: more, smaller nodes are easier to find on
  # the spot market and lose fewer participants when one is reclaimed.
  ranked = sort([
    for name, candidate in local.candidates :
    format(
      "%08d|%04d|%s",
      ceil(var.workload.replicas / candidate.seats_per_node) * candidate.vcpu,
      candidate.vcpu,
      name,
    )
  ])

  fits          = length(local.ranked) > 0
  instance_type = local.fits ? element(split("|", local.ranked[0]), 2) : "unschedulable"

  seats_per_node = local.fits ? local.candidates[local.instance_type].seats_per_node : 0
  nodes          = local.fits ? ceil(var.workload.replicas / local.seats_per_node) : 0

  # Every seat on a node keeps its own copy of the dataset in ephemeral
  # storage, plus the image layers and the container logs.
  disk_gib = ceil(local.seats_per_node * var.workload.disk_gib * 1.15) + 40
}
