# The read-only workshop dataset and the permission to read it.
#
# Bucket and access are one design decision, not two: a bucket nobody may read
# is useless and a role granting access to nothing is meaningless. Keeping them
# together means the caller never assembles an IRSA trust policy, and there is
# never a window where one exists without the other.
#
# The policies are built with jsonencode rather than aws_iam_policy_document.
# That keeps them known at plan time, so `tofu test` can assert on who is
# allowed to do what without an AWS account.

terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

resource "aws_s3_bucket" "this" {
  bucket = var.name

  # The bucket holds a redistributable copy of workshop material; losing it
  # costs a re-upload, so nothing blocks teardown.
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# A failed `aws s3 sync` of a 20 GB dataset leaves multipart uploads that are
# invisible in the console listing and bill as storage indefinitely. This is the
# single most common way a "destroyed" workshop keeps costing money.
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_iam_role" "reader" {
  name = "${var.name}-reader"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = var.reader.oidc_provider_arn }

      # Scoped to the exact service account: another pod in the same cluster
      # presenting a token for a different account is refused.
      Condition = {
        StringEquals = {
          "${var.reader.oidc_issuer_host}:sub" = "system:serviceaccount:${var.reader.namespace}:${var.reader.service_account}"
          "${var.reader.oidc_issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "reader" {
  role = aws_iam_role.reader.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["arn:aws:s3:::${var.name}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = ["arn:aws:s3:::${var.name}"]
      },
    ]
  })
}
