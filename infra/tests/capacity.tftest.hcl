# Packing rules. Pure computation, so these need neither credentials nor mocks.

run "one_seat_gets_the_smallest_machine_that_fits" {
  command = plan

  module { source = "./modules/capacity" }

  variables {
    workload = { replicas = 1, vcpu = 1, memory_gib = 4, disk_gib = 30 }
  }

  assert {
    condition     = output.plan.instance_type == "m6i.large"
    error_message = "A single small seat should not provision a large instance."
  }

  assert {
    condition     = output.plan.nodes == 1
    error_message = "One seat needs one node."
  }
}

# The default headcount, asserted so that the figures quoted in
# docs/07-cost-and-lifecycle.md cannot quietly stop being true.
run "the_default_workshop_gets_two_small_nodes" {
  command = plan

  module { source = "./modules/capacity" }

  variables {
    workload = { replicas = 5, vcpu = 1, memory_gib = 4, disk_gib = 30 }
  }

  assert {
    condition     = output.plan.instance_type == "m6i.xlarge"
    error_message = "Five small seats should not need more than an xlarge."
  }

  assert {
    condition     = output.plan.nodes == 2 && output.plan.seats_per_node == 3
    error_message = "docs/07-cost-and-lifecycle.md quotes 2 nodes of 3 seats."
  }

  assert {
    condition     = output.plan.disk_gib == 144
    error_message = "docs/07-cost-and-lifecycle.md quotes 144 GB node disks."
  }
}

# Deliberately a larger workshop than the default: the packing rule is what is
# under test, and it is only visible when seats have to share.
run "seats_are_packed_rather_than_given_a_node_each" {
  command = plan

  module { source = "./modules/capacity" }

  variables {
    workload = { replicas = 25, vcpu = 1, memory_gib = 4, disk_gib = 30 }
  }

  assert {
    condition     = output.plan.seats_per_node > 1
    error_message = "A 1 vCPU / 4 GiB seat must share a node with others."
  }

  assert {
    condition     = output.plan.nodes * output.plan.seats_per_node >= 25
    error_message = "The plan must have room for every participant."
  }
}

run "node_disk_covers_every_seat_s_copy_of_the_dataset" {
  command = plan

  module { source = "./modules/capacity" }

  variables {
    workload = { replicas = 10, vcpu = 2, memory_gib = 8, disk_gib = 40 }
  }

  assert {
    condition     = output.plan.disk_gib >= output.plan.seats_per_node * 40
    error_message = "Nodes would run out of disk once every seat synced the dataset."
  }
}

run "a_large_seat_moves_to_a_larger_instance" {
  command = plan

  module { source = "./modules/capacity" }

  variables {
    workload = { replicas = 4, vcpu = 8, memory_gib = 48, disk_gib = 60 }
  }

  assert {
    condition     = output.plan.instance_type == "m6i.4xlarge"
    error_message = "A 48 GiB seat does not fit in a 32 GiB instance at 85% schedulable."
  }
}

run "an_impossible_seat_is_refused_at_plan_time" {
  command = plan

  module { source = "./modules/capacity" }

  variables {
    workload = { replicas = 1, vcpu = 64, memory_gib = 8, disk_gib = 10 }
  }

  expect_failures = [output.plan]
}

run "a_mistyped_headcount_is_refused_before_it_bills" {
  command = plan

  module { source = "./modules/capacity" }

  variables {
    workload  = { replicas = 5000, vcpu = 1, memory_gib = 4, disk_gib = 30 }
    max_nodes = 20
  }

  expect_failures = [output.plan]
}
