provider "aws" {
  region = var.region
}

resource "aws_vpc" "devopsallstars" {
  cidr_block = var.vpc_cidr_block
  tags = {
    name = var.tags
  }
}

/***************************
* Shared Backend Resources *
****************************
|
* DDB Tables for state locking
|
* Terraform Backend Bucket & Versioning
|
* Lambda Deployment Bucket & Versioning
|
* Lambda Execution Role & Policy
|
***************************/

// DynamoDB Tables for State Locking  | state migration: https://developer.hashicorp.com/terraform/cli/commands/state/mv
module "ddb" {
  source      = "./modules/ddb"
  table_names = var.table_names
  tags = {
    Name = var.tags
  }
}

// S3 Bucket for Terraform Backend
resource "aws_s3_bucket" "devops_backend_bucket" {
  bucket = var.devops_backend_bucket
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "backend_bucket_versioning" {
  bucket = aws_s3_bucket.devops_backend_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

// Lambda Bucket
resource "aws_s3_bucket" "lambda_bucket" {
  bucket = var.lambda_bucket
  tags = {
    name = var.tags
  }
}

resource "aws_s3_bucket_versioning" "lambda_bucket_versioning" {
  bucket = aws_s3_bucket.lambda_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

// IAM Resources | https://registry.terraform.io/providers/hashicorp/aws/2.33.0/docs/guides/iam-policy-documents
resource "aws_iam_role" "devopsallstars_gha_role" {
  name = var.gha_role_name
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : "arn:aws:iam::${var.account_id}:oidc-provider/token.actions.githubusercontent.com"
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "token.actions.githubusercontent.com:aud" : "sts.amazonaws.com"
          },
          "StringLike" : {
            "token.actions.githubusercontent.com:sub" : "repo:${var.repo_name}:*"
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
      "arn:aws:s3:::${var.tags}*",
      "arn:aws:s3:::${var.tags}/*"
    ]
  }

  statement {
    actions = [
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:GetFunction",
      "lambda:InvokeFunction"
    ]

    resources = [
      "arn:aws:lambda:${var.region}:${var.account_id}:*",
    ]
  }

  statement {
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:DescribeImages"
    ]

    resources = [
      "*"
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