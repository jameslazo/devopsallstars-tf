output "ddb_table_names" {
  value = { for ky, tb in aws_dynamodb_table.tf_state_locks : ky => tb.name }
}