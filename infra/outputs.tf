output "image_repository" {
  description = "Push the participant image here (`make image-push`)."
  value       = module.registry.repository_url
}

output "dataset_uri" {
  description = "Mirror ./data here (`make data-push`)."
  value       = module.dataset.uri
}

output "capacity_plan" {
  description = "Hardware chosen for the requested seats."
  value       = module.cluster.capacity_plan
}

output "participant_url_command" {
  description = "Run this to get the address to hand out (`make url`)."
  value       = module.platform.access_command
}
