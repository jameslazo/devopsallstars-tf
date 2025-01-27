output "aws_vpc_id" {
  value = aws_vpc.devopsallstars.id
}

output "lambda_execution_role" {
  value = {
    arn  = aws_iam_role.lambda_exec.arn
    name = aws_iam_role.lambda_exec.name
  }
}

output "aws_iam_role_policy_attachment" {
  value = aws_iam_role_policy_attachment.lambda_policy.id
}

output "lambda_bucket" {
  value = aws_s3_bucket.lambda_bucket.id
}