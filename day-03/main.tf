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
            - lambda_exec{.arn,.name}
        aws_iam_role_policy_attachment:
          lambda_sns_publish_attachment: "ID"
************************************/

data "terraform_remote_state" "shared_state" {
  backend = "s3"
  config = {
    bucket = "${var.devops_backend_bucket}" # S3 bucket storing the source state
    key    = "shared/terraform.tfstate"     # Path to the source state file
    region = "${var.region}"
  }
}

// Day 3 Data Lake
resource "aws_s3_bucket" "data_lake_bucket_raw" {
  bucket = var.data_lake_bucket_raw
  tags = {
    name = var.tags
  }
}

resource "aws_s3_bucket" "data_lake_bucket_extracted" {
  bucket = var.data_lake_bucket_extracted
  tags = {
    name = var.tags
  }
}

// Athena Bucket
resource "aws_s3_bucket" "athena_bucket" {
  bucket = var.athena_bucket
  tags = {
    name = var.tags
  }
}

resource "aws_s3_object" "api_lambda" {
  bucket = data.terraform_remote_state.shared_state.outputs.lambda_bucket

  key    = "day03_api_lambda.zip"
  source = data.archive_file.datalake_api_lambda_zip.output_path

  etag = filemd5(data.archive_file.datalake_api_lambda_zip.output_path)
}

resource "aws_s3_object" "extract_lambda" {
  bucket = data.terraform_remote_state.shared_state.outputs.lambda_bucket

  key    = "day03_extract_lambda.zip"
  source = data.archive_file.datalake_extract_lambda_zip.output_path

  etag = filemd5(data.archive_file.datalake_extract_lambda_zip.output_path)
}

// Lambda Resources | https://developer.hashicorp.com/terraform/tutorials/aws/lambda-api-gateway#create-and-upload-lambda-function-archive

data "archive_file" "datalake_api_lambda_zip" {
  type        = "zip"
  source_dir  = "../../day03-datalake/src/api_lambda/"
  output_path = "../../day03_api_lambda.zip"
  excludes    = ["__pycache__/*"]
}

resource "aws_lambda_function" "devops_day03_api_lambda" {
  depends_on       = [data.archive_file.datalake_api_lambda_zip]
  function_name    = "devops_day03_api_lambda"
  handler          = "main.lambda_handler"
  runtime          = "python3.12"
  role             = data.terraform_remote_state.shared_state.outputs.lambda_execution_role.arn
  timeout          = 10
  filename         = "../../day03_api_lambda.zip"
  source_code_hash = filebase64sha256("../../day03_api_lambda.zip")
  environment {
    variables = {
      SPORTS_DATA_API_KEY = var.nba_api_key
      NBA_ENDPOINT        = "https://api.sportsdata.io/v3/nba/scores/json/Players"
      DEVOPS_PREFIX       = "devopsallstars-day03-"
      RAW_BUCKET          = var.raw_data_env
    }
  }
}

data "archive_file" "datalake_extract_lambda_zip" {
  type        = "zip"
  source_dir  = "../../day03-datalake/src/extract_lambda/"
  output_path = "../../day03_extract_lambda.zip"
  excludes    = ["__pycache__/*"]
}

resource "aws_lambda_function" "devops_day03_extract_lambda" {
  depends_on       = [data.archive_file.datalake_extract_lambda_zip]
  function_name    = "devops_day03_extract_lambda"
  handler          = "main.lambda_handler"
  runtime          = "python3.12"
  role             = data.terraform_remote_state.shared_state.outputs.lambda_execution_role.arn
  timeout          = 10
  filename         = "../../day03_api_lambda.zip"
  source_code_hash = filebase64sha256("../../day03_extract_lambda.zip")
  environment {
    variables = {
      DEVOPS_PREFIX    = "devopsallstars-day03-"
      RAW_BUCKET       = var.raw_data_env
      EXTRACTED_BUCKET = var.extracted_data_env
    }
  }
}

// S3 Bucket Notification Configuration
resource "aws_lambda_permission" "s3_invoke_permission" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.devops_day03_extract_lambda.function_name
  principal     = "s3.amazonaws.com"

  source_arn = aws_s3_bucket.data_lake_bucket_raw.arn
}

// S3 Bucket Notification Configuration
resource "aws_s3_bucket_notification" "raw_bucket_notification" {
  bucket = aws_s3_bucket.data_lake_bucket_raw.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.devops_day03_extract_lambda.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".json" # Filter by object key suffix
  }

  depends_on = [aws_lambda_permission.s3_invoke_permission]
}

// Glue|Athena Resources
resource "aws_glue_catalog_database" "glueopsallstars" {
  name = "glueopsallstars"
}

resource "aws_glue_catalog_table" "glueopsallstars_table" {
  name          = "glueopsallstars_table"
  database_name = aws_glue_catalog_database.glueopsallstars.name
  table_type    = "EXTERNAL_TABLE"
  parameters = {
    "classification" = "json"
  }
  storage_descriptor {
    location      = "s3://${aws_s3_bucket.data_lake_bucket_extracted.bucket}/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"
    ser_de_info {
      name                  = "SerdeInfo"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }
    columns {
      name = "playerid"
      type = "int"
    }
    columns {
      name = "firstname"
      type = "string"
    }
    columns {
      name = "lastname"
      type = "string"
    }
    columns {
      name = "team"
      type = "string"
    }
    columns {
      name = "position"
      type = "string"
    }
    columns {
      name = "points"
      type = "int"
    }
  }
}

resource "aws_glue_crawler" "glueopsallstars_crawler" {
  name          = "glueopsallstars_crawler"
  role          = aws_iam_role.glue_service_role.arn
  database_name = aws_glue_catalog_database.glueopsallstars.name
  s3_target {
    path = "s3://${var.data_lake_bucket_extracted}/"
  }
}

resource "aws_athena_workgroup" "devopsallstars" {
  name = "devopsallstars"
  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    result_configuration {
      output_location = "s3://${var.athena_bucket}/athena-results/"
    }
  }
}

// IAM Resources | https://registry.terraform.io/providers/hashicorp/aws/2.33.0/docs/guides/iam-policy-documents
resource "aws_iam_policy" "api_lambda_s3_raw_policy" {
  name        = "lambda_s3raw_policy"
  description = "Policy allowing Lambda to put api data into S3 bucket"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.data_lake_bucket_raw.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_lambda_s3raw_attachment" {
  role       = data.terraform_remote_state.shared_state.outputs.lambda_execution_role.name
  policy_arn = aws_iam_policy.api_lambda_s3_raw_policy.arn
}

resource "aws_iam_policy" "extract_lambda_s3_policy" {
  name        = "lambda_s3extract_policy"
  description = "Policy allowing Lambda to put extracted data into S3 bucket"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.data_lake_bucket_extracted.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.data_lake_bucket_raw.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "extract_lambda_s3_attachment" {
  role       = data.terraform_remote_state.shared_state.outputs.lambda_execution_role.name
  policy_arn = aws_iam_policy.extract_lambda_s3_policy.arn
}

resource "aws_iam_role" "glue_service_role" {
  name = "glue-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "glue.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_access_s3" {
  role       = aws_iam_role.glue_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role" "athena_query_execution_role" {
  name = "athena-query-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "athena.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "athena_glue_s3_access" {
  role       = aws_iam_role.athena_query_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonAthenaFullAccess"
}

resource "aws_iam_policy" "athena_s3_access_policy" {
  name        = "AthenaS3AccessPolicy"
  description = "Custom policy allowing Athena to interact with S3 for query results."

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["s3:GetObject", "s3:ListBucket"],
        Resource = [
          "arn:aws:s3:::your-data-lake-bucket",
          "arn:aws:s3:::your-data-lake-bucket/*"
        ]
      },
      {
        Effect = "Allow",
        Action = "s3:PutObject",
        Resource = [
          "arn:aws:s3:::your-athena-query-results-bucket",
          "arn:aws:s3:::your-athena-query-results-bucket/*"
        ]
      }
    ]
  })
}

resource "aws_s3_bucket_policy" "raw_data_lake_bucket_policy" {
  bucket = aws_s3_bucket.data_lake_bucket_raw.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = data.terraform_remote_state.shared_state.outputs.lambda_execution_role.arn
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.data_lake_bucket_raw.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_policy" "extracted_data_lake_bucket_policy" {
  bucket = aws_s3_bucket.data_lake_bucket_extracted.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = data.terraform_remote_state.shared_state.outputs.lambda_execution_role.arn
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.data_lake_bucket_extracted.arn}/*"
      }
    ]
  })
}