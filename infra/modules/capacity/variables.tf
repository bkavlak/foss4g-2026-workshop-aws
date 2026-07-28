variable "workload" {
  description = <<-EOT
    The shape of one participant seat and how many are needed. Everything the
    module needs to answer "what hardware does this workshop require?".
  EOT
  type = object({
    replicas   = number
    vcpu       = number
    memory_gib = number
    disk_gib   = number
  })

  validation {
    condition     = var.workload.replicas >= 1 && var.workload.vcpu > 0 && var.workload.memory_gib > 0
    error_message = "A workshop needs at least one seat with positive cpu and memory."
  }
}

variable "max_nodes" {
  description = "Upper bound on nodes, as a guard against a mistyped headcount."
  type        = number
  default     = 20
}
