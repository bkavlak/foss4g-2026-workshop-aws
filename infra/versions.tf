terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.75" }
    # Held at 2.x deliberately. The provider's 3.0 release moved `kubernetes`
    # from a block to an attribute, and more importantly `tofu test`'s
    # mock_provider cannot construct values for the nested attribute types v3
    # introduces -- it panics rather than failing. Until that is fixed upstream,
    # moving to v3 means losing the platform tests entirely.
    helm = { source = "hashicorp/helm", version = "~> 2.17" }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Workshop  = var.workshop_name
      ManagedBy = "opentofu"
    }
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.cluster.endpoint
    cluster_ca_certificate = base64decode(module.cluster.certificate_authority)

    # Tokens are minted at apply time rather than stored in state, so a plan
    # made yesterday still applies today.
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.cluster.name, "--region", var.region]
    }
  }
}
