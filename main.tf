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


