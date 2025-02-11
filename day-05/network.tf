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


/**********
* Subnets *
**********/
resource "aws_subnet" "media_subnet_pub" {
  cidr_block              = var.cidr_block_pub
  map_public_ip_on_launch = true
  vpc_id                  = data.terraform_remote_state.shared_state.outputs.aws_vpc_id
  tags = {
    Name = "api_ec2-primary"
  }
}

resource "aws_subnet" "media_subnet_priv" {
  cidr_block              = var.cidr_block_priv
  map_public_ip_on_launch = false
  vpc_id                  = data.terraform_remote_state.shared_state.outputs.aws_vpc_id
  tags = {
    Name = "api_ec2-secondary"
  }
}


/**********************************
* Internet Gateway & Route Tables *
**********************************/


/******************
* Security Groups *
******************/
resource "aws_security_group" "ecs_task" {
  name        = "${var.project_name}-ecs-task-sg"
  description = "Security group for ECS tasks"
  vpc_id      = data.terraform_remote_state.shared_state.outputs.aws_vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow HTTPS traffic; adjust as needed
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # Allow all outbound traffic
    cidr_blocks = ["0.0.0.0/0"]
  }
}
