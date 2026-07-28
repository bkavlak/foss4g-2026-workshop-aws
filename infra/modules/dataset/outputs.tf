output "uri" {
  description = "s3:// prefix the participant pods sync from, and `make data-push` writes to."
  value       = "s3://${aws_s3_bucket.this.bucket}"
}

output "reader_role_arn" {
  description = "Role the participant service account assumes to read the dataset."
  value       = aws_iam_role.reader.arn
}
