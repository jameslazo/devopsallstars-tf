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
  bucket = var.weather_bucket_name
  tags = {
    name = var.tags
  }
}

// Day 3 Data Lake
resource "aws_s3_bucket" "data_lake_bucket_raw" {
  bucket = var.data_lake_bucket_raw
  tags = {
    name = var.tags
  }
}

resource "aws_s3_bucket" "data_lake_bucket_transformed" {
  bucket = var.data_lake_bucket_transformed
  tags = {
    name = var.tags
  }
}

// Lambda Bucket
resource "aws_s3_bucket" "lambda_bucket" {
  bucket = var.lambda_bucket
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
  environment {
    variables = {
      NBA_API_KEY = var.nba_api_key
      SNS_TOPIC_ARN = aws_sns_topic.game_day_topic.arn
    }
  }
}

data "archive_file" "datalake_api_lambda_zip" {
  type = "zip"
  source_dir  = "../day03-datalake/src/api_lambda"
  output_path = "../day03_api_lambda.zip"
  excludes = ["__pycache__/*"]
}

resource "aws_lambda_function" "devops_day03_api_lambda" {
  function_name = "devops_day03_api_lambda"
  handler = "main.lambda_handler"
  runtime = "python3.12"
  role = aws_iam_role.lambda_exec.arn
  filename = "../day03_api_lambda.zip"
  source_code_hash = filebase64sha256("../day03_api_lambda.zip")
  environment {
    variables = {
      SPORTS_DATA_API_KEY = var.nba_api_key
      NBA_ENDPOINT = "https://api.sportsdata.io/v3/nba/scores/json/Players"
      DEVOPS_PREFIX = "devopsallstars-day03-"
      RAW_BUCKET = var.data_lake_bucket_raw
    }
  }
}

data "archive_file" "datalake_transform_lambda_zip" {
  type = "zip"
  source_dir  = "../day03-datalake/src/transform_lambda"
  output_path = "../day03_transform_lambda.zip"
  excludes = ["__pycache__/*"]
}

resource "aws_lambda_function" "devops_day03_transform_lambda" {
  function_name = "devops_day03_transform_lambda"
  handler = "main.lambda_handler"
  runtime = "python3.12"
  role = aws_iam_role.lambda_exec.arn
  filename = "../day03_api_lambda.zip"
  source_code_hash = filebase64sha256("../day03_transform_lambda.zip")
  environment {
    variables = {
      DEVOPS_PREFIX = "devopsallstars-day03-"
      RAW_BUCKET = var.data_lake_bucket_raw
      TRANSFORMED_BUCKET = var.data_lake_bucket_transformed
    }
  }
}

// SNS Resources
resource "aws_sns_topic" "game_day_topic" {
  name = var.topic_name
}

/* Used for CloudWatch to publish to SNS
resource "aws_sns_topic_policy" "devopsallstars_sns_policy" {
  arn = aws_sns_topic.game_day_topic.arn
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
        "Resource": "${aws_sns_topic.game_day_topic.arn}"
      }
    ]
  })
}
*/

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
      aws_s3_bucket.data_lake_bucket_raw.arn,
      "${aws_s3_bucket.data_lake_bucket_raw.arn}/*",
      aws_lambda_function.devops_day02_lambda.arn,
      aws_lambda_function.devops_day03_api_lambda.arn,
      aws_lambda_function.devops_day03_transform_lambda.arn
    ]
  }
}

resource "aws_iam_role_policy" "devopsallstars_gha_policy_attachment" {
  name   = "devopsallstars_gha_policy_attachment"
  role   = aws_iam_role.devopsallstars_gha_role.name
  policy = data.aws_iam_policy_document.devopsallstars_gha_role_policy.json
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

resource "aws_iam_policy" "api_lambda_s3_raw_policy" {
  name = "lambda_sns_publish_policy"
  description = "Policy allowing Lambda to put api data into S3 bucket"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "s3:PutObject"
        Resource = "${aws_s3_bucket.data_lake_bucket_raw.arn}/*"
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "api_lambda_s3raw_attachment" {
  role = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.api_lambda_s3_raw_policy.arn
}

resource "aws_iam_policy" "transform_lambda_s3_policy" {
  name = "lambda_sns_publish_policy"
  description = "Policy allowing Lambda to put transformed data into S3 bucket"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.data_lake_bucket_transformed.arn}/*"
      },
      {
        Effect = "Allow"
        Action = "s3:GetObject"
        Resource = "${aws_s3_bucket.data_lake_bucket_raw.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "transform_lambda_s3_attachment" {
  role = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.transform_lambda_s3_policy.arn
}