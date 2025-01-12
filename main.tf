provider "aws" {
  region = var.region
}

resource "aws_vpc" "devopsallstars" {
  cidr_block = var.vpc_cidr_block
  tags = {
    name = var.tags
  }
}

// S3 Resources
// Day 1 Weather Data
resource "aws_s3_bucket" "weather_data_bucket" {
  bucket = var.bucket_name
  tags = {
    name = var.tags
  }
}

// Day 2 Lambda Bucket
resource "aws_s3_bucket" "lambda_bucket" {
  bucket = "devopsallstars-lambda-bucket"
  tags = {
    name = var.tags
  }
}

resource "aws_s3_object" "notification_lambda" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "day02_lambda.zip"
  source = data.archive_file.lambda_notification_zip.output_path

  etag = filemd5(data.archive_file.lambda_notification_zip.output_path)
}

// Lambda Resources | https://developer.hashicorp.com/terraform/tutorials/aws/lambda-api-gateway#create-and-upload-lambda-function-archive
data "archive_file" "lambda_notification_zip" {
  type = "zip"

  source_dir  = "../day02-notifications/src/"
  output_path = "../day02_lambda.zip"
  excludes = ["__pycache__/*"]
}


resource "aws_lambda_function" "devops_day02_lambda" {
  function_name = "devops_day02_lambda"
  handler = "lambda_function.lambda_handler"
  runtime = "python3.12"
  role = aws_iam_role.lambda_exec.arn
  filename = "../day02_lambda.zip"
  source_code_hash = filebase64sha256("../day02_lambda.zip")
}

resource "aws_lambda_permission" "cloudwatch_lambda_invocation" {
  statement_id = "AllowExecutionFromCloudWatch"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.devops_day02_lambda.function_name
  principal = "events.amazonaws.com"
}

// SNS Resources
resource "aws_sns_topic" "game_day_topic" {
  name = var.topic_name
}

// EventBridge Resources | https://medium.com/@nagarjun_nagesh/terraform-aws-eventbridge-rule-21ba1fc1d93e
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

// IAM Resources | https://registry.terraform.io/providers/hashicorp/aws/2.33.0/docs/guides/iam-policy-documents
resource "aws_iam_role" "devopsallstars_gha_role" {
  name  = var.gha_role_name
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
            "Federated": "arn:aws:iam::${var.account_id}:oidc-provider/token.actions.githubusercontent.com"
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
          "StringEquals": {
              "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
          },
          "StringLike": {
              "token.actions.githubusercontent.com:sub": "repo:${var.repo_name}:*"
          }
        }
      }
    ]
})
}

data "aws_iam_policy_document" "devopsallstars_gha_role_policy" {
  statement {
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:GetObjectAcl",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:DeleteObject",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:GetFunction",
      "lambda:InvokeFunction"
    ]

    resources = [
      aws_s3_bucket.weather_data_bucket.arn,
      "${aws_s3_bucket.weather_data_bucket.arn}/*",
      aws_lambda_function.devops_day02_lambda.arn
    ]
  }
}

resource "aws_iam_role_policy" "devopsallstars_gha_policy_attachment" {
  name   = "devopsallstars_gha_policy_attachment"
  role   = aws_iam_role.devopsallstars_gha_role.name
  policy = data.aws_iam_policy_document.devopsallstars_gha_role_policy.json
}

resource "aws_sns_topic_policy" "devopsallstars_sns_policy" {
  arn    = aws_sns_topic.game_day_topic.arn
  policy = jsonencode({
    "Version": "2012-10-17",
    "Id": "sns-publish",
    "Statement": [
      {
        "Sid": "sns-publish",
        "Effect": "Allow",
        "Principal": {
          "Service": "events.amazonaws.com"
        },
        "Action": "sns:Publish",
        "Resource": "${aws_sns_topic.game_day_topic.arn}",
      }
    ]
  })
}

// https://stackoverflow.com/questions/57288992/terraform-how-to-create-iam-role-for-aws-lambda-and-deploy-both
resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}