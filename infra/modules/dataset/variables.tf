variable "name" {
  type = string
}

variable "reader" {
  description = <<-EOT
    The Kubernetes identity that may read the dataset, and the cluster whose
    tokens are trusted to speak for it.
  EOT
  type = object({
    oidc_provider_arn = string
    oidc_issuer_host  = string
    namespace         = string
    service_account   = string
  })
}
