output "vpc_id" {
  value = module.vpc.vpc_id
}

output "node_subnet_ids" {
  description = "Where cluster nodes belong. Private; egress via NAT."
  value       = module.vpc.private_subnets
}

output "load_balancer_subnet_ids" {
  description = "Where the participant-facing load balancer belongs."
  value       = module.vpc.public_subnets
}
