variable "subnet_ids" {
  type = list(string)
}

variable "instance_type" {
  type = string
}

variable "vpc_security_group_ids" {
  type = list(string)
}

variable "tags" {
  type = map(string)
}

variable "user_data" {
  type = string
}

variable "instance_count" {
  type = number
}

variable "iam_instance_profile" {
  type = string
}