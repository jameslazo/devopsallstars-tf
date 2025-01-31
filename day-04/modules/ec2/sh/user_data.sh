#!/bin/bash

# Log commands
exec > /var/log/user_data.log 2>&1

# Environment variables
export ECR_REPO_URI="${ECR_REPO_URI}"
export ECR_REPO_NAME="${ECR_REPO_NAME}"
export AWS_REGION="${AWS_REGION}"
export IMAGE_TAG="latest"
export CONTAINER_NAME="sports-api"

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

# https://reintech.io/blog/zero-downtime-deployments-docker-compose-rolling-updates
cat <<EOF > docker-compose.yml
name: $CONTAINER_NAME

services:
  $CONTAINER_NAME:
    image: $ECR_REPO_URI:$IMAGE_TAG
    ports:
      - "80:8080"
    deploy:
      update_config:
        parallelism: 1
        delay: 10s
      restart_policy:
        condition: on-failure
EOF

cat <<ECRCRON > /opt/ecr-cron.sh
#!/bin/bash

# Log commands
exec > /var/log/docker-compose.log 2>&1

# Check for image tag, execute docker-compose commands
if aws ecr describe-images \
  --repository-name "$ECR_REPO_NAME" \
  --region "$AWS_REGION" \
  --query "imageDetails[?contains(imageTags, '$IMAGE_TAG')]" \
  --output text; then
    echo "Image exists in ECR"
    docker-compose pull "$ECR_REPO_URI:$IMAGE_TAG" 
    docker-compose up -d
else
    echo "No image with $IMAGE_TAG in ECR"
fi
ECRCRON

chmod +x /opt/ecr-cron.sh

# Schedule cron job
echo "*/5 * * * * /opt/ecr-cron.sh" > /etc/cron.d/ecr-cron

# Grab instance metadata
echo "exporting token for IMDSv2"
export TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 >> instance_ip.txt
curl -v -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/info >> instance_role.txt