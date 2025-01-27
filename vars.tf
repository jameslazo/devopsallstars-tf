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

variable "gha_role_name" {
  default = ""
}

variable "account_id" {
  default = ""
}

variable "repo_name" {
  default = ""
}

variable "table_names" {
  description = "List of DynamoDB table names to create"
  type        = list(string)
}