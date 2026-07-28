variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnets the nodes are placed in."
  type        = list(string)
}

variable "workload" {
  description = "The participant seats this cluster must be able to hold."
  type = object({
    replicas   = number
    vcpu       = number
    memory_gib = number
    disk_gib   = number
  })
}

variable "kubernetes_version" {
  type    = string
  default = "1.31"
}
