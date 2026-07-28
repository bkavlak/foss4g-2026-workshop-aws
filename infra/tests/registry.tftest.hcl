mock_provider "aws" {}

run "images_are_scanned_and_old_ones_expire" {
  command = plan

  module { source = "./modules/registry" }

  variables {
    name = "test-workshop"
  }

  assert {
    condition     = aws_ecr_repository.this.image_scanning_configuration[0].scan_on_push
    error_message = "Participant images should be scanned when pushed."
  }

  assert {
    condition     = aws_ecr_repository.this.image_tag_mutability == "IMMUTABLE"
    error_message = "A republished tag would leave some nodes serving stale layers."
  }

  assert {
    condition     = aws_ecr_repository.this.force_delete
    error_message = "`make down` must not be blocked by leftover images."
  }

  assert {
    condition     = jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[0].selection.countNumber == 5
    error_message = "Image retention should be bounded."
  }
}
