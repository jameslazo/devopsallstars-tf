output "instance_map" {
  value = { for idx, id in aws_instance.api_ec2 : idx => id.id }
}