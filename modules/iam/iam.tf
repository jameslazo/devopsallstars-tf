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