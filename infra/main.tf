# Composition root. Each module below owns one decision of the workshop; this
# file only states how they relate, and deliberately contains no logic beyond
# reading the roster the maintainer minted.

locals {
  roster_path = "${path.module}/${var.roster_directory}/roster.json"
  roster      = jsondecode(file(local.roster_path))["participants"]
}

# A cluster sized for a headcount the roster does not cover would leave
# participants without logins, which is not visible until the workshop starts.
check "roster_matches_headcount" {
  assert {
    condition     = length(local.roster) >= var.participant_count
    error_message = "roster.json has ${length(local.roster)} accounts but participant_count is ${var.participant_count}. Re-run `make roster`."
  }
}

module "network" {
  source = "./modules/network"

  name   = var.workshop_name
  region = var.region
}

module "registry" {
  source = "./modules/registry"

  name = var.workshop_name
}

module "cluster" {
  source = "./modules/cluster"

  name       = var.workshop_name
  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.node_subnet_ids

  workload = {
    replicas   = var.participant_count
    vcpu       = var.seat.vcpu
    memory_gib = var.seat.memory_gib
    disk_gib   = var.seat.disk_gib
  }
}

module "dataset" {
  source = "./modules/dataset"

  name = "${var.workshop_name}-data"

  reader = {
    oidc_provider_arn = module.cluster.oidc_provider_arn
    oidc_issuer_host  = module.cluster.oidc_issuer_host
    namespace         = local.namespace
    service_account   = "workshop-participant"
  }
}

module "platform" {
  source = "./modules/platform"

  namespace = local.namespace
  image = {
    repository = module.registry.repository_url
    tag        = var.image_tag
  }
  seat   = var.seat
  roster = local.roster

  dataset = {
    uri             = module.dataset.uri
    reader_role_arn = module.dataset.reader_role_arn
  }
}

locals {
  namespace = "workshop"
}
