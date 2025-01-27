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


/******************************
* infrastructure architecture *
*******************************
|
* VPC (shared)
|
* Internet Gateway & Route Tables
|
* Subnets
|
* Security Groups
|
* api_EC2 Instances
|
* IAM Roles & Policies
| 
******************************/

provider "aws" {
    region = var.region
}

// Internet Gateway & Route Tables
resource "aws_internet_gateway" "doas_ig" {
  depends_on = [
    data.terraform_remote_state.shared_state.outputs.aws_vpc,
  ]
  vpc_id = data.terraform_remote_state.shared_state.outputs.aws_vpc.aws_vpc_id
  tags = {
    "Name" = "doas-ig"
  }
}

resource "aws_route_table" "doas_pubrt" {
  depends_on = [
    aws_internet_gateway.doas_ig,
  ]
  vpc_id = data.terraform_remote_state.shared_state.outputs.aws_vpc.aws_vpc_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.doas_ig.id
  }
  tags = {
    "Name" = "doas-pubrt"
  }
}

resource "aws_route_table_association" "doas_rta" {
  depends_on = [
    aws_subnet.api_ec2_primary,
    aws_route_table.doas_pubrt
  ]
  subnet_id      = aws_subnet.api_ec2_primary.id
  route_table_id = aws_route_table.doas_pubrt.id
}

// Subnets
resource "aws_subnet" "api_ec2_primary" {
  depends_on = [
    aws_vpc.wp_vpc,
  ]
  cidr_block              = var.cidr_block_subnet_api_ec2_primary
  availability_zone       = var.availability_zone_primary
  map_public_ip_on_launch = true
  vpc_id                  = data.terraform_remote_state.shared_state.outputs.aws_vpc.aws_vpc_id
  tags = {
    "Name" = "api_ec2-primary"
  }
}

resource "aws_subnet" "api_ec2_failover" {
  depends_on = [
    aws_vpc.wp_vpc,
  ]
  cidr_block              = var.cidr_block_subnet_api_ec2_failover
  availability_zone       = var.availability_zone_failover
  map_public_ip_on_launch = true
  vpc_id                  = data.terraform_remote_state.shared_state.outputs.aws_vpc.aws_vpc_id
  tags = {
    "Name" = "api_ec2-failover"
  }
}

// Security Groups
resource "aws_security_group" "api_ec2_sg" {
  name        = "api_ec2-bastion"
  description = "Bastion to api_ec2 & RDS"
  vpc_id      = data.terraform_remote_state.shared_state.outputs.aws_vpc.aws_vpc_id

  ingress {
    description = "elb"
    from_port   = 0
    to_port     = 65535
    protocol    = "TCP"
    security_groups = [aws_security_group.api_ec2_elb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "api_ec2_elb_sg" {
  name        = "api_ec2-elb"
  description = "elb sg"
  vpc_id      = data.terraform_remote_state.shared_state.outputs.aws_vpc.aws_vpc_id

  ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
  /* Uncomment for HTTPS
  ingress {
    description = "https"
    from_port   = 443
    to_port     = 443
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
  */
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.cidr_block_supernet]
  }
}

