/************************************
* data from shared tf state outputs *
*************************************
  shared_state:
    outputs:
      vpc:
        aws_vpc:
          aws_vpc_id: "ID"
        aws_internet_gateway:
          igw_id: "ID"
************************************/
data "terraform_remote_state" "shared_state" {
  backend = "s3"
  config = {
    bucket = "${var.devops_backend_bucket}" # S3 bucket storing the source state
    key    = "shared/terraform.tfstate"     # Path to the source state file
    region = "${var.aws_region}"
  }
}


/**********
* Subnets *
**********/
resource "aws_subnet" "subnet_media_pub" {
  cidr_block              = var.cidr_block_pub
  map_public_ip_on_launch = true
  vpc_id                  = data.terraform_remote_state.shared_state.outputs.aws_vpc_id
  tags                    = var.tags
}
/*
resource "aws_subnet" "subnet_media_priv" {
  cidr_block              = var.cidr_block_priv
  map_public_ip_on_launch = false
  vpc_id                  = data.terraform_remote_state.shared_state.outputs.aws_vpc_id
  tags = var.tags
}
*/

/***************
* Route Tables *
***************/
resource "aws_route_table" "pubrt_media" {
  vpc_id = data.terraform_remote_state.shared_state.outputs.aws_vpc_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = data.terraform_remote_state.shared_state.outputs.igw_id
  }
  tags = var.tags
}

resource "aws_route_table_association" "rta_public" {
  depends_on = [
    aws_subnet.subnet_media_pub,
    aws_route_table.pubrt_media
  ]
  subnet_id      = aws_subnet.subnet_media_pub.id
  route_table_id = aws_route_table.pubrt_media.id
}
/*
resource "aws_route_table_association" "rta_private" {
  depends_on = [
    aws_subnet.subnet_media_pub,
    aws_route_table.pubrt_media
  ]
  subnet_id      = aws_subnet.subnet_media_priv.id
  route_table_id = aws_route_table.pubrt_media.id
}
*/

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
    cidr_blocks = ["0.0.0.0/0"] # Allow HTTPS traffic; adjust as needed
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Allow all outbound traffic
    cidr_blocks = ["0.0.0.0/0"]
  }
}
