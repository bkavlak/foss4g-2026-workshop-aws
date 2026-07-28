output "repository_url" {
  description = "Push and pull address, without a tag."
  value       = aws_ecr_repository.this.repository_url
}
