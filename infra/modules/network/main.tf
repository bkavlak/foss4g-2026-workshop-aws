# The network a workshop cluster runs in.
#
# Callers say only what the workshop is called. Address ranges, availability
# zone selection, NAT strategy and the subnet tags that let EKS discover where
# to place load balancers are all decisions this module owns, because none of
# them change the workshop and all of them would otherwise have to be repeated
# correctly at every call site.

terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  cidr = "10.0.0.0/16"

  # Three zones: enough for spot capacity to be found somewhere, few enough
  # that a single NAT gateway is a defensible cost trade for a one-day event.
  zones = slice(data.aws_availability_zones.available.names, 0, 3)

  private = [for i, _ in local.zones : cidrsubnet(local.cidr, 4, i)]
  public  = [for i, _ in local.zones : cidrsubnet(local.cidr, 8, i + 48)]
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  # Exact, not a range. A community module that moves between `tofu plan` and
  # `tofu apply` can change what is destroyed, and nothing would warn you.
  version = "5.21.0"

  name = var.name
  cidr = local.cidr

  azs             = local.zones
  private_subnets = local.private
  public_subnets  = local.public

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # EKS reads these tags to decide where to attach internal and internet-facing
  # load balancers. Getting them wrong fails at service-creation time with a
  # message that does not mention subnets, so they belong here and nowhere else.
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
}
