output "aws_vpc_id" {
  value = aws_vpc.devopsallstars.id
}

output "lambda_execution_role_arn" {
  value = aws_iam_role.lambda_exec.arn
}

output "aws_iam_role_policy_attachment" {
  value = aws_iam_role_policy_attachment.lambda_sns_publish_attachment.id
}

