#!/bin/bash

# Log commands
exec > /var/log/user_data.log 2>&1

# Environment variables
echo ECR_REPO_URI="${ECR_REPO_URI}" >> /etc/environment
echo ECR_REPO_NAME="${ECR_REPO_NAME}" >> /etc/environment
echo AWS_REGION="${AWS_REGION}" >> /etc/environment
echo IMAGE_TAG="latest" >> /etc/environment
echo CONTAINER_NAME="sports-api" >> /etc/environment
. /etc/environment

echo "alias dp='docker pull $ECR_REPO_URI:$IMAGE_TAG'" >> /home/ec2-user/.bashrc
echo "alias dr='docker pull $ECR_REPO_URI:$IMAGE_TAG'" >> /home/ec2-user/.bashrc
. /home/ec2-user/.bashrc

# Install and start Docker
yum update -y
yum install docker -y
service docker start
newgrp docker
usermod -aG docker ec2-user

cd /home/ec2-user

# Install Docker Compose
curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

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

cat <<ECRCRED > /usr/local/bin/ecr-credentials.sh
#!/bin/bash

# Log commands
exec > /var/log/ecr-credentials.log 2>&1

aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_REPO_URI
ECRCRED
chmod +x /usr/local/bin/ecr-credentials.sh
/usr/local/bin/ecr-credentials.sh

cat <<ECRCRON > /usr/local/bin/ecr-pull.sh
#!/bin/bash

# Log commands
exec > /var/log/docker-compose.log 2>&1

# Pull and deploy latest image
docker-compose pull
docker-compose up -d
ECRCRON
chmod +x /usr/local/bin/ecr-pull.sh
/usr/local/bin/ecr-pull.sh

# Schedule cron jobs
echo "0 */12 * * * /usr/local/bin/ecr-credentials.sh" > /etc/cron.d/ecr-credentials
echo "*/15 * * * * /usr/local/bin/ecr-cron.sh" > /etc/cron.d/ecr-cron

# Grab instance metadata
echo "exporting token for IMDSv2"
export TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 >> instance_ip.txt
curl -v -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/info >> instance_role.txt
