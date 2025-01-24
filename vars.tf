variable "region" {
  default = ""
}

variable "vpc_cidr_block" {
  default = ""
}

variable "tags" {
  default = {}
}

variable "lambda_bucket" {
  default = ""
}

variable "devops_backend_bucket" {
  default = ""
}

variable "weather_bucket_name" {
  default = ""
}

variable "data_lake_bucket_raw" {
  default = ""
}

variable "data_lake_bucket_extracted" {
  default = ""
}

variable "athena_bucket" {
  default = ""
}

variable "topic_name" {
  default = ""
}

variable "event_rule_name" {
  default = ""
}

variable "gha_role_name" {
  default = ""
}

variable "account_id" {
  default = ""
}

variable "repo_name" {
  default = ""
}

variable "nba_api_key" {
  default = ""
}

variable "raw_data_env" {
  default = ""
}

variable "extracted_data_env" {
  default = ""
}

variable "table_names" {
  description = "List of DynamoDB table names to create"
  type        = list(string)
}