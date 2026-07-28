variable "workshop_name" {
  description = "Short name for this workshop. Prefixes every resource; must be DNS-safe."
  type        = string
  default     = "geo-workshop"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.workshop_name))
    error_message = "Use 3-31 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "participant_count" {
  description = "How many people will attend. Determines cluster size and must match the roster."
  type        = number
  default     = 5
}

variable "image_tag" {
  description = "Tag of the participant image already pushed to the workshop registry."
  type        = string
  default     = "v1"
}

variable "seat" {
  description = "Resources one participant gets. Raise memory before cpu for raster work."
  type = object({
    vcpu       = number
    memory_gib = number
    disk_gib   = number
  })
  default = {
    vcpu       = 1
    memory_gib = 4
    disk_gib   = 30
  }
}

variable "roster_directory" {
  description = "Where `workshop provision` wrote roster.json."
  type        = string
  default     = "../roster"
}
