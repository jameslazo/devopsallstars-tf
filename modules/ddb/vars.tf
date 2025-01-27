variable "table_names" {
  description = "List of ddb tables to provision"
  type = list(string)
}

variable "tags" {
  type = map(string)
}