variable "namespace" {
  type    = string
  default = "workshop"
}

variable "release_name" {
  type    = string
  default = "workshop"
}

variable "image" {
  description = "Participant environment image, split so the tag can change without the repository."
  type = object({
    repository = string
    tag        = string
  })
}

variable "seat" {
  description = "What one participant may consume."
  type = object({
    vcpu       = number
    memory_gib = number
    disk_gib   = number
  })
}

variable "dataset" {
  description = "Read-only data mounted at /data. Set uri to \"\" to run without one."
  type = object({
    uri             = string
    reader_role_arn = string
  })
}

variable "roster" {
  description = "username -> scrypt verifier, as produced by `workshop provision`."
  type        = map(any)
  sensitive   = true
}
