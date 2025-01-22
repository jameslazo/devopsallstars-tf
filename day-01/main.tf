// Day 1 Weather Data
resource "aws_s3_bucket" "weather_data_bucket" {
  bucket = var.weather_bucket_name
  tags = {
    name = var.tags.name
  }
}