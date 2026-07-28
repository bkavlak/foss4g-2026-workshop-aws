# A Kubernetes cluster sized for a given number of participant seats.
#
# The interface is a description of the workshop, not of AWS: callers state how
# many seats of what shape they need and receive a cluster that can hold them.
# Instance families, node counts, disk sizing, spot configuration, IRSA and the
# addon set are all consequences, and all hidden.

terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

module "capacity" {
  source   = "../capacity"
  workload = var.workload
}

locals {
  plan = module.capacity.plan
}

module "eks" {
  source = "terraform-aws-modules/eks/aws"
  # Exact, for the same reason as the VPC module: see modules/network/main.tf.
  version = "20.37.2"

  cluster_name    = var.name
  cluster_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # Participants reach the hub through a load balancer, never the API server.
  # The endpoint stays public so the maintainer can run `helm` and `kubectl`
  # from a laptop without a bastion.
  cluster_endpoint_public_access = true

  # Without this the maintainer who ran `tofu apply` cannot use `kubectl`
  # against their own cluster, which is a surprising and expensive lesson to
  # learn ten minutes before a workshop.
  enable_cluster_creator_admin_permissions = true

  enable_irsa = true

  cluster_addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = {}
    eks-pod-identity-agent = {}
  }

  eks_managed_node_groups = {
    seats = {
      instance_types = [local.plan.instance_type]

      # Spot: a workshop is interruption-tolerant (a reclaimed seat restarts
      # in under a minute) and this is the single largest cost saving
      # available. Two extra nodes of headroom absorb a reclamation.
      capacity_type = "SPOT"

      min_size     = local.plan.nodes
      desired_size = local.plan.nodes
      max_size     = local.plan.nodes + 2

      disk_size = local.plan.disk_gib
    }
  }
}
