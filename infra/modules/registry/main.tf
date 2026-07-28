# Where the participant image lives.
#
# Owns the retention and scanning policy so that no caller has to decide, and
# so that tearing a workshop down does not leave paid-for image storage behind.

terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

resource "aws_ecr_repository" "this" {
  name = var.name

  # Immutable. Republishing a fixed image under the same tag looks convenient
  # and silently fails: nodes that already cached that tag keep serving the old
  # layers, so some participants get the fix and others do not. Pushing a new
  # tag and applying with it makes the rollout observable.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  # A workshop registry is disposable; refusing to delete it because images
  # remain would only ever be an obstacle to `make down`.
  force_delete = true
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 5 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 5 }
      action       = { type = "expire" }
    }]
  })
}
