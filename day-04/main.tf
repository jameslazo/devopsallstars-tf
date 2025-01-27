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
* api_EC2 Instances
|
* IAM Roles & Policies
| 
******************************/

provider "aws" {
    region = var.region
}

/**********************************
* Internet Gateway & Route Tables *
**********************************/
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


/**********
* Subnets *
**********/
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


/******************
* Security Groups *
******************/
resource "aws_security_group" "api_ec2_sg" {
  name        = "api_ec2-sg"
  description = "SG for api_ec2 instances"
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


/****************
* EC2 Instances *
****************/

resource "aws_instance" "api" {
    depends_on = [
    aws_security_group.api_ec2_sg,
    aws_subnet.api_ec2_primary,
  ]

  ami           = data.aws_ami.latest_ami.id
  instance_type = var.instance_type_wp
  vpc_security_group_ids = [aws_security_group.api_ec2_sg.id]
  subnet_id       = aws_subnet.api_ec2_primary.id
  
  // Comment out to update user_data
  lifecycle {
    ignore_changes = [user_data]
  }

  // User data
  user_data = <<-EOF
    #!/bin/bash
    # Log commands
    exec > /var/log/user_data.log 2>&1
    
    # Install and start Docker
    yum update -y
    yum install docker -y
    service docker start
    usermod -aG docker ec2-user
    newgrp docker
    curl -SL "https://github.com/docker/compose/releases/download/v2.29.3/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    cd /home/ec2-user
    pwd
    
    # Grab instance metadata
    echo "exporting token for IMDSv2"
    export TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    echo $TOKEN
    curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 >> instance_ip.txt
    curl -v -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/info >> instance_role.txt
    
  EOF

  tags = {
    Name = var.tags
  }
}

data "aws_ami" "latest_ami" {
  most_recent = true
  owners = ["amazon"]
  filter {
  name = "name"
  values = ["al2023-ami-2023*"]
  }
  filter {
  name = "root-device-type"
  values = ["ebs"]
  }
  filter {
  name = "virtualization-type"
  values = ["hvm"]
  }
  filter {
  name = "architecture"
  values = ["x86_64"]
  }
}

// ELB Block
resource "aws_lb" "api_ec2_lb" {
  name               = "api-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.api_ec2_elb_sg.id]
  subnets            = [aws_subnet.api_ec2_primary.id, aws_subnet.api_ec2_failover.id]

  enable_deletion_protection = false
  enable_http2 = true
  idle_timeout = 60
  ip_address_type = "ipv4"

  tags = {
    Name = var.tags
  }
}

resource "aws_lb_target_group" "api_ec2_tg" {
  depends_on = [
    aws_lb.api_lb
  ]
  name     = "api-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wp_vpc.id

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
  load_balancer_arn = aws_lb.api_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_tg.arn
  }
}

resource "aws_lb_listener" "wp_listener" {
  load_balancer_arn = aws_lb.api_lb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_tg.arn
  }
}