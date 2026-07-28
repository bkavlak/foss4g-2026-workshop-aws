# The dataset bucket and its IRSA grant, against a mocked AWS provider.
# Nothing here creates or reads a real resource.

mock_provider "aws" {}

run "only_the_participant_service_account_may_read_the_data" {
  command = plan

  module { source = "./modules/dataset" }

  variables {
    name = "test-workshop-data"
    reader = {
      oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-central-1.amazonaws.com/id/ABC"
      oidc_issuer_host  = "oidc.eks.eu-central-1.amazonaws.com/id/ABC"
      namespace         = "workshop"
      service_account   = "workshop-participant"
    }
  }

  assert {
    condition = strcontains(
      aws_iam_role.reader.assume_role_policy,
      "system:serviceaccount:workshop:workshop-participant",
    )
    error_message = "Any pod in the cluster could read the dataset, not just participant seats."
  }

  assert {
    condition     = strcontains(aws_iam_role.reader.assume_role_policy, "sts.amazonaws.com")
    error_message = "A token minted for another audience would be accepted."
  }
}

run "participants_cannot_write_to_the_dataset" {
  command = plan

  module { source = "./modules/dataset" }

  variables {
    name = "test-workshop-data"
    reader = {
      oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/example"
      oidc_issuer_host  = "example"
      namespace         = "workshop"
      service_account   = "workshop-participant"
    }
  }

  assert {
    condition = alltrue(flatten([
      for statement in jsondecode(aws_iam_role_policy.reader.policy).Statement :
      [for action in statement.Action : !strcontains(action, "Put") && !strcontains(action, "Delete")]
    ]))
    error_message = "Participants must not be able to modify the shared dataset."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_policy
    error_message = "The dataset bucket must never become publicly readable."
  }
}
