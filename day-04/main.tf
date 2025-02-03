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
* ALB Resources
|
* API Gateway Resources
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
  name                 = "devops-ecr"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = var.tags
}


/**********************************
* Internet Gateway & Route Tables *
**********************************/
resource "aws_internet_gateway" "doas_ig" {
  vpc_id = data.terraform_remote_state.shared_state.outputs.aws_vpc_id
  tags = {
    Name = "doas-ig"
  }
}

resource "aws_route_table" "doas_pubrt" {
  depends_on = [
    aws_internet_gateway.doas_ig,
  ]
  vpc_id = data.terraform_remote_state.shared_state.outputs.aws_vpc_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.doas_ig.id
  }
  tags = {
    Name = "doas-pubrt"
  }
}

resource "aws_route_table_association" "doas_rta_primary" {
  depends_on = [
    aws_subnet.api_ec2_primary,
    aws_route_table.doas_pubrt
  ]
  subnet_id      = aws_subnet.api_ec2_primary.id
  route_table_id = aws_route_table.doas_pubrt.id
}

resource "aws_route_table_association" "doas_rta_secondary" {
  depends_on = [
    aws_subnet.api_ec2_primary,
    aws_route_table.doas_pubrt
  ]
  subnet_id      = aws_subnet.api_ec2_secondary.id
  route_table_id = aws_route_table.doas_pubrt.id
}


/**********
* Subnets *
**********/
resource "aws_subnet" "api_ec2_primary" {
  cidr_block              = var.cidr_block_subnet_api_ec2_primary
  availability_zone       = var.availability_zone_primary
  map_public_ip_on_launch = true
  vpc_id                  = data.terraform_remote_state.shared_state.outputs.aws_vpc_id
  tags = {
    Name = "api_ec2-primary"
  }
}

resource "aws_subnet" "api_ec2_secondary" {
  cidr_block              = var.cidr_block_subnet_api_ec2_secondary
  availability_zone       = var.availability_zone_secondary
  map_public_ip_on_launch = true
  vpc_id                  = data.terraform_remote_state.shared_state.outputs.aws_vpc_id
  tags = {
    Name = "api_ec2-secondary"
  }
}


/******************
* Security Groups *
******************/
resource "aws_security_group" "api_ec2_sg" {
  name        = "api_ec2-sg"
  description = "SG for api_ec2 instances"
  vpc_id      = data.terraform_remote_state.shared_state.outputs.aws_vpc_id

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
  vpc_id      = data.terraform_remote_state.shared_state.outputs.aws_vpc_id

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
module "api_ec2_instances" {
  source                 = "./modules/ec2"
  instance_type          = var.instance_type
  instance_count         = 2
  subnet_ids             = [aws_subnet.api_ec2_primary.id, aws_subnet.api_ec2_secondary.id]
  vpc_security_group_ids = [aws_security_group.api_ec2_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_instance_profile_sports_api.name
  tags                   = var.tags
  user_data              = data.template_file.user_data.rendered
}

data "template_file" "user_data" {
  template = file("${path.module}/modules/ec2/sh/user_data.sh")

  vars = {
    AWS_REGION    = "${var.region}"
    ECR_REPO_URI  = "${aws_ecr_repository.devops_ecr.repository_url}"
    ECR_REPO_NAME = "${aws_ecr_repository.devops_ecr.name}"
  }
}


/****************
* ALB Resources *
****************/
resource "aws_lb" "api_ec2_lb" {
  name               = "api-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.api_ec2_elb_sg.id]
  subnets            = [aws_subnet.api_ec2_primary.id, aws_subnet.api_ec2_secondary.id]

  enable_deletion_protection = false
  enable_http2               = true
  idle_timeout               = 60
  ip_address_type            = "ipv4"

  tags = var.tags
}

resource "aws_lb_target_group" "api_ec2_tg" {
  depends_on = [
    aws_lb.api_ec2_lb
  ]
  name     = "api-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.terraform_remote_state.shared_state.outputs.aws_vpc_id

  health_check {
    path                = "/sports"
    protocol            = "HTTP"
    healthy_threshold   = 5
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
  }

  tags = var.tags
}

resource "aws_lb_target_group_attachment" "api_ec2_tg_attachment" {
  for_each         = module.api_ec2_instances.instance_map
  target_group_arn = aws_lb_target_group.api_ec2_tg.arn
  target_id        = each.value
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

/* Uncomment for SSM VPC Endpoint
resource "aws_vpc_endpoint" "doas_vpc_endpoint" {
  vpc_id = data.terraform_remote_state.shared_state.outputs.aws_vpc_id
  service_name = "com.amazonaws.${var.region}.ssm"
  route_table_ids = [aws_route_table.doas_pubrt.id]
}
*/


/************************ | https://andrewtarry.com/posts/aws-http-gateway-with-cognito-and-terraform/
* API Gateway Resources * | https://hands-on.cloud/terraform-api-gateway/
************************/
resource "aws_apigatewayv2_api" "sports_api" {
  depends_on    = [aws_lb_listener.api_ec2_listener_http]
  name          = "sports-api"
  protocol_type = "HTTP"
}

/* Uncomment for VPC Link (private)
resource "aws_apigatewayv2_vpc_link" "doas_vpc_link" {
  name               = "doas-vpc-link"
  security_group_ids = [aws_security_group.api_ec2_sg.id]
  subnet_ids         = [aws_subnet.api_ec2_primary.id, aws_subnet.api_ec2_secondary.id]
}
*/

resource "aws_apigatewayv2_route" "sports_api_route" {
  api_id             = aws_apigatewayv2_api.sports_api.id
  route_key          = "GET /sports"
  target             = "integrations/${aws_apigatewayv2_integration.sports_api_integration.id}"
  authorization_type = "NONE"
}

resource "aws_apigatewayv2_integration" "sports_api_integration" {
  api_id             = aws_apigatewayv2_api.sports_api.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = "http://${aws_lb.api_ec2_lb.dns_name}/sports"
}

resource "aws_apigatewayv2_deployment" "sports_api_deployment" {
  api_id     = aws_apigatewayv2_api.sports_api.id
}

resource "aws_apigatewayv2_stage" "dev" {
  api_id        = aws_apigatewayv2_api.sports_api.id
  name          = "dev"
  auto_deploy   = true
  deployment_id = aws_apigatewayv2_deployment.sports_api_deployment.id
}


/***************
* IAM Policies * 
***************/
// EC2 Role, Policy, Policy Attachment & Instance Profile | https://beltrani.com/ec2-instance-and-container-access-to-ecr-and-other-services/
resource "aws_iam_role" "ec2_assume_role" {
  name = "ec2-ecr-access-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

// ECR + SSM | https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-add-permissions-to-existing-profile.html
resource "aws_iam_policy" "ecr_policy" {
  name = "ec2-ecr-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:DescribeImages"
        ]

        Resource = "arn:aws:ecr:${var.region}:${var.account_id}:repository/${aws_ecr_repository.devops_ecr.name}"
      },
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ],
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetEncryptionConfiguration"
        ],
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_role_policy_attachment" {
  role       = aws_iam_role.ec2_assume_role.name
  policy_arn = aws_iam_policy.ecr_policy.arn
}

resource "aws_iam_instance_profile" "ec2_instance_profile_sports_api" {
  name = "ec2-instance-profile-sports-api"
  role = aws_iam_role.ec2_assume_role.name
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.sports_api.api_endpoint
}