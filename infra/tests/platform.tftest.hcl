# The translation from workshop vocabulary into JupyterHub's. Renders the
# values template against a mocked Helm provider: no cluster, no chart pull.

mock_provider "helm" {}

variables {
  image  = { repository = "123.dkr.ecr.eu-central-1.amazonaws.com/geo-workshop", tag = "v1" }
  seat   = { vcpu = 1, memory_gib = 4, disk_gib = 30 }
  roster = { user1 = { salt = "00", hash = "11", n = 16384, r = 8, p = 1 } }
}

run "a_configured_dataset_is_synced_before_the_seat_starts" {
  command = plan

  module { source = "./modules/platform" }

  variables {
    dataset = {
      uri             = "s3://geo-workshop-data"
      reader_role_arn = "arn:aws:iam::123456789012:role/geo-workshop-data-reader"
    }
  }

  assert {
    condition = length(
      yamldecode(helm_release.workshop.values[0]).jupyterhub.singleuser.initContainers
    ) == 1
    error_message = "Participants would open JupyterLab against an empty /data."
  }

  assert {
    condition = contains(
      yamldecode(helm_release.workshop.values[0]).jupyterhub.singleuser.initContainers[0].command,
      "s3://geo-workshop-data",
    )
    error_message = "The sync init container does not point at the dataset bucket."
  }

  assert {
    condition = (
      yamldecode(helm_release.workshop.values[0]).dataset.awsRoleArn ==
      "arn:aws:iam::123456789012:role/geo-workshop-data-reader"
    )
    error_message = "Without the role annotation the sync has no permission to read S3."
  }
}

run "no_dataset_means_no_init_container_at_all" {
  command = plan

  module { source = "./modules/platform" }

  variables {
    dataset = { uri = "", reader_role_arn = "" }
  }

  assert {
    condition = !can(
      yamldecode(helm_release.workshop.values[0]).jupyterhub.singleuser.initContainers
    )
    error_message = "An init container syncing from nowhere would stall every seat."
  }
}

run "seat_limits_reach_jupyterhub" {
  command = plan

  module { source = "./modules/platform" }

  variables {
    seat    = { vcpu = 2, memory_gib = 8, disk_gib = 60 }
    dataset = { uri = "", reader_role_arn = "" }
  }

  assert {
    condition     = yamldecode(helm_release.workshop.values[0]).jupyterhub.singleuser.memory.limit == "8G"
    error_message = "One participant could starve the others on a shared node."
  }

  assert {
    condition     = yamldecode(helm_release.workshop.values[0]).jupyterhub.singleuser.image.tag == "v1"
    error_message = "Seats would not run the image that was pushed."
  }
}
