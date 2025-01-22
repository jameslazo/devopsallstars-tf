variable "table_names" {
  description = "List of ddb tables to provision"
  type = list(string)
}

variable "ddb_tags" {
  description = "Tags to apply to resources"
  type = map(string)
}