output "name" {
  value = module.eks.cluster_name
}

output "endpoint" {
  value = module.eks.cluster_endpoint
}

output "certificate_authority" {
  description = "Base64 PEM bundle for verifying the API server."
  value       = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "oidc_issuer_host" {
  description = "Issuer without its scheme, the form IAM trust conditions require."
  value       = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
}

output "capacity_plan" {
  description = "How the requested seats were packed onto hardware. Reporting only."
  value       = module.capacity.plan
}
