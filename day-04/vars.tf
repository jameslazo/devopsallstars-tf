variable "cidr_block_vpc" {
    type = string
    default = "172.16.0.0/12"
}

variable "region" {
  default = "us-east-1"
}

variable "vpc_cidr_block" {
  default = ""
}

variable "tags" {
  default = {}
}

variable "devops_backend_bucket" {
  default = ""
}

variable "availability_zone_primary" {
    type = string
    default = "us-east-1a"
}

variable "availability_zone_failover" {
    type = string
    default = "us-east-1b"
}

variable "cidr_block_subnet_api_ec2_primary" {
    type = string
    default = "172.16.0.0/24"
}

variable "cidr_block_subnet_api_ec2_failover" {
    type = string
    default = "172.16.1.0/24"
}

variable "cidr_block_supernet" {
    type = string
    default = "172.16.0.0/22"
}

variable "instance_type_wp" {
    type = string
    default = ""
}