// Lambda Resources | https://developer.hashicorp.com/terraform/tutorials/aws/lambda-api-gateway#create-and-upload-lambda-function-archive
data "archive_file" "lambda_notification_zip" {
  type = "zip"
  source_dir = "../../day02-notifications/src/"
  output_path = "../../day02_lambda.zip"
  excludes = ["__pycache__/*"]
}

resource "aws_lambda_function" "devops_day02_lambda" {
  depends_on = [data.archive_file.lambda_notification_zip]
  function_name = "devops_day02_lambda"
  handler = "lambda_function.lambda_handler"
  runtime = "python3.12"
  role = aws_iam_role.lambda_exec.arn
  filename = "../../day02_lambda.zip"
  source_code_hash = filebase64sha256("../../day02_lambda.zip")
  environment {
    variables = {
      NBA_API_KEY = var.nba_api_key
      SNS_TOPIC_ARN = aws_sns_topic.game_day_topic.arn
    }
  }
}

// EventBridge Resources | https://medium.com/@nagarjun_nagesh/terraform-aws-eventbridge-rule-21ba1fc1d93e
resource "aws_lambda_permission" "cloudwatch_lambda_invocation" {
  statement_id = "AllowExecutionFromCloudWatch"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.devops_day02_lambda.function_name
  principal = "events.amazonaws.com"
}

resource "aws_cloudwatch_event_rule" "devops_notification_event_rule" {
  name = var.event_rule_name
  description = "cron job for lambda"
  schedule_expression = "cron(0 14 * * ? *)" // 9AM ET every day (2PM UTC) | https://www.baeldung.com/cron-expressions
}

resource "aws_cloudwatch_event_target" "devops_notification_event_target" {
  rule = aws_cloudwatch_event_rule.devops_notification_event_rule.name
  target_id = "devops_notification_event_target"
  arn = aws_lambda_function.devops_day02_lambda.arn
}

resource "aws_iam_policy" "lambda_sns_publish_policy" {
  name = "lambda_sns_publish_policy"
  description = "Policy allowing Lambda to publish to SNS topic"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sns:Publish"
        Resource = "${aws_sns_topic.game_day_topic.arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_sns_publish_attachment" {
  role = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_sns_publish_policy.arn
}