#!/bin/bash
# Log commands
exec > /var/log/user_data.log 2>&1

# Environment variables
ECR_REPO_URI="${aws_ecr_repository.devops_ecr.repository_url}"
AWS_REGION="${var.region}"
IMAGE_TAG="latest"
CONTAINER_NAME="sports-api"

# Install and start Docker
yum update -y
yum install docker -y
service docker start
usermod -aG docker ec2-user
newgrp docker

cd /home/ec2-user

# Install Docker Compose
# curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
# chmod +x /usr/local/bin/docker-compose

aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO_URI

docker pull $ECR_REPO_URI:$IMAGE_TAG
docker run -d --name $CONTAINER_NAME -p 80:8080 $ECR_REPO_URI:$IMAGE_TAG


# Grab instance metadata
echo "exporting token for IMDSv2"
export TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
echo $TOKEN
curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 >> instance_ip.txt
curl -v -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/info >> instance_role.txt