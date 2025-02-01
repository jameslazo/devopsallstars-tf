variable "region" {
  default = "us-east-1"
}

variable "tags" {
  type = map(string)
}

variable "devops_backend_bucket" {
  type =  string
}

variable "availability_zone_primary" {
  type    = string
  default = "us-east-1a"
}

variable "availability_zone_failover" {
  type    = string
  default = "us-east-1b"
}

variable "cidr_block_subnet_api_ec2_primary" {
  type    = string
  default = "172.16.0.0/24"
}

variable "cidr_block_subnet_api_ec2_failover" {
  type    = string
  default = "172.16.1.0/24"
}

variable "cidr_block_supernet" {
  type    = string
  default = "172.16.0.0/22"
}

variable "instance_type" {
  type    = string
  default = ""
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Blog subdomain"
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID"
  type        = string
  default     = ""
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
  default     = ""
}