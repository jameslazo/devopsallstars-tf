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
* Provider
|
* VPC (shared)
|
* Internet Gateway & Route Tables
|
* Subnets
|
* Security Groups
|
* EC2 Instances
|
* IAM Roles & Policies
| 
******************************/


/***********
* Provider *
***********/
provider "aws" {
  region = var.region
}


/***********
* ECR Repo *
***********/
resource "aws_ecr_repository" "devops_ecr" {
  name = "devops-ecr"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = {
    "Name" = var.tags
  }
}


/**********************************
* Internet Gateway & Route Tables *
**********************************/
resource "aws_internet_gateway" "doas_ig" {
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


/**********
* Subnets *
**********/
resource "aws_subnet" "api_ec2_primary" {
  cidr_block              = var.cidr_block_subnet_api_ec2_primary
  availability_zone       = var.availability_zone_primary
  map_public_ip_on_launch = true
  vpc_id                  = data.terraform_remote_state.shared_state.outputs.aws_vpc.aws_vpc_id
  tags = {
    "Name" = "api_ec2-primary"
  }
}

resource "aws_subnet" "api_ec2_failover" {
  cidr_block              = var.cidr_block_subnet_api_ec2_failover
  availability_zone       = var.availability_zone_failover
  map_public_ip_on_launch = true
  vpc_id                  = data.terraform_remote_state.shared_state.outputs.aws_vpc.aws_vpc_id
  tags = {
    "Name" = "api_ec2-failover"
  }
}


/******************
* Security Groups *
******************/
resource "aws_security_group" "api_ec2_sg" {
  name        = "api_ec2-sg"
  description = "SG for api_ec2 instances"
  vpc_id      = data.terraform_remote_state.shared_state.outputs.aws_vpc.aws_vpc_id

  ingress {
    description     = "elb"
    from_port       = 0
    to_port         = 65535
    protocol        = "TCP"
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


/****************
* EC2 Instances *
****************/
resource "aws_instance" "api_ec2" {
  depends_on = [
    aws_security_group.api_ec2_sg,
    aws_subnet.api_ec2_primary,
    aws_ecr_repository.devops_ecr
  ]

  ami                    = data.aws_ami.latest_ami.id
  instance_type          = var.instance_type_wp
  vpc_security_group_ids = [aws_security_group.api_ec2_sg.id]
  subnet_id              = aws_subnet.api_ec2_primary.id

  // https://developer.hashicorp.com/terraform/tutorials/state/resource-lifecycle
  lifecycle {
    create_before_destroy = true
  }

  // User data | 
  user_data = data.template_file.user_data.rendered

  tags = {
    Name = var.tags
  }
}

data "aws_ami" "latest_ami" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023*"]
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}


data template_file "user_data" {
  template = file("${path.module}/user_data.sh")
}


/****************
* ALB Resources *
****************/
resource "aws_lb" "api_ec2_lb" {
  name               = "api-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.api_ec2_elb_sg.id]
  subnets            = [aws_subnet.api_ec2_primary.id, aws_subnet.api_ec2_failover.id]

  enable_deletion_protection = false
  enable_http2               = true
  idle_timeout               = 60
  ip_address_type            = "ipv4"

  tags = {
    Name = var.tags
  }
}

resource "aws_lb_target_group" "api_ec2_tg" {
  depends_on = [
    aws_lb.api_ec2_lb
  ]
  name     = "api-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.terraform_remote_state.shared_state.outputs.aws_vpc.aws_vpc_id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    port                = 80
    healthy_threshold   = 5
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
  }

  tags = {
    Name = var.tags
  }
}

resource "aws_lb_target_group_attachment" "api_ec2_tg_attachment" {
  target_group_arn = aws_lb_target_group.api_ec2_tg.arn
  target_id        = aws_instance.api_ec2.id
  port             = 80
}

resource "aws_lb_listener" "api_ec2_listener_http" {
  load_balancer_arn = aws_lb.api_ec2_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_ec2_tg.arn
  }
}

resource "aws_lb_listener" "api_ec2_listener" {
  load_balancer_arn = aws_lb.api_ec2_lb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_ec2_tg.arn
  }
}


/***************
* IAM Policies * 
***************/
// SSM Policy | https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-add-permissions-to-existing-profile.html
resource "aws_iam_policy" "aws_ssm_policy" {
  name        = "aws-ssm-policy"
  description = "Policy for SSM"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:GetEncryptionConfiguration"
        ],
        "Resource" : "*"
      }
    ]
  })
}

// EC2 Role, Policy, Policy Attachment & Instance Profile
resource "aws_iam_role" "ec2_assume_role" {
  name               = "ec2-ecr-access-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "ecr_policy" {
  name   = "ec2-ecr-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer"
        ]
        Effect    = "Allow"
        Resource  = "arn:aws:ecr:${var.region}:${var.account_id}:repository/${aws_ecr_repository.devops_ecr.name}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_role_policy_attachment" {
  role       = aws_iam_role.ec2_assume_role.name
  policy_arn = aws_iam_policy.ecr_policy.arn
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2-instance-profile"
  role = aws_iam_role.ec2_assume_role.name
}
