resource "aws_instance" "api_ec2" {
    ami           = data.aws_ami.latest_ami.id
    instance_type = var.instance_type
    count = var.instance_count
    subnet_id     = element(var.subnet_ids, count.index)
    security_groups = var.security_groups
    tags = var.tags
    user_data = var.user_data
    lifecycle {
      create_before_destroy = true
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