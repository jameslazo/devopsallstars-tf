variable "region" {
  default = ""
}

variable "vpc_cidr_block" {
  default = ""
}

variable "tags" {
  default = {
    Name = ""
  }
}

variable "bucket_name" {
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
