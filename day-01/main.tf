provider "aws" {
  region = var.region
}

// Day 1 Weather Data
resource "aws_s3_bucket" "weather_data_bucket" {
  bucket = var.weather_bucket_name
  tags = {
    name = var.tags
  }
}

data "terraform_remote_state" "shared_state" {
  backend = "s3"
  config = {
    bucket = "${var.devops_backend_bucket}"   # S3 bucket storing the source state
    key = "shared/terraform.tfstate"  # Path to the source state file
    region = "${var.region}"
  }
}