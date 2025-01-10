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
resource "aws_s3_bucket" "weather_data_bucket" {
  bucket = var.bucket_name
  tags = {
    name = var.tags
  }
}

// SNS Resources
resource "aws_sns_topic" "game_day_topic" {
  name = var.topic_name
}

// Lambda Resources 
resource "aws_lambda_function" "devops_day02_lambda" {
  function_name = "devops_day02_lambda"
  handler = "lambda_function.lambda_handler"
  runtime = "python3.12"
  role = aws_iam_role.lambda_exec_role.arn
  filename = "../day02_lambda.zip"
  source_code_hash = filebase64sha256("../day02_lambda.zip")
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
      "s3:DeleteObject"
    ]

    resources = [
      aws_s3_bucket.weather_data_bucket.arn,
      "${aws_s3_bucket.weather_data_bucket.arn}/*"
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

resource "aws_iam_role" "lambda_exec_role" {
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
