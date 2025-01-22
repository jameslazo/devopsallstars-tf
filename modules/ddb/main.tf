resource "aws_dynamodb_table" "tf_state_locks" {
  for_each = toset(var.table_names)

  name = "${each.key}-tf-state-locks"
  hash_key = "LockID"
  billing_mode = "PAY_PER_REQUEST"
  attribute {
    name = "LockID"
    type = "S"
  }
  tags = {
    Name = var.ddb_tags["Name"]
  }
}