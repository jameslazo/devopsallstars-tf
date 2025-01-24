provider "aws" {
  region = var.region
}

/************************************
* data from shared tf state outputs *
*************************************
  shared_state:
    outputs:
      vpc:
        aws_vpc:
          aws_vpc_id: "ID"
      ddb:
        aws_dynamodb_table:
          keys: 
            - day0{1,2,3,4,5,6}
      s3:
        aws_s3_bucket:
          lambda_bucket: "ID"
      iam:
        aws_iam_role:
          keys:
            - lambda_execution_role{.arn,.name}
        aws_iam_role_policy_attachment:
          lambda_sns_publish_attachment: "ID"
************************************/

data "terraform_remote_state" "shared_state" {
  backend = "s3"
  config = {
    bucket = "${var.devops_backend_bucket}"   # S3 bucket storing the source state
    key = "shared/terraform.tfstate"  # Path to the source state file
    region = "${var.region}"
  }
}

// SNS Resources
resource "aws_sns_topic" "game_day_topic" {
  name = var.topic_name
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
  role = data.terraform_remote_state.shared_state.outputs.lambda_execution_role.arn
  filename = "../../day02_lambda.zip"
  source_code_hash = filebase64sha256("../../day02_lambda.zip")
  environment {
    variables = {
      NBA_API_KEY = var.nba_api_key
      SNS_TOPIC_ARN = aws_sns_topic.game_day_topic.arn
    }
  }
}

resource "aws_s3_object" "notification_lambda" {
  bucket = data.terraform_remote_state.shared_state.outputs.lambda_bucket
  key = "day02_lambda.zip"
  source = data.archive_file.lambda_notification_zip.output_path

  etag = filemd5(data.archive_file.lambda_notification_zip.output_path)
}

// IAM Resources
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
  role = data.terraform_remote_state.shared_state.outputs.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_sns_publish_policy.arn
}