provider "aws" {
  region = var.region
}

resource "aws_vpc" "devopsallstars" {
  cidr_block = var.vpc_cidr_block
}

resource "aws_s3_bucket" "weather_data_bucket" {
  bucket = var.bucket_name

  tags = {
    Name = var.bucket_tags
  }
}

resource "aws_iam_role" "devopsallstars_gha_role" {
  name  = var.role_name
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
