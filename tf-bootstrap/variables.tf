variable state_bucket_name {
  type    = string
  # A random bucket name by default
  default = "poc-dev-tfstate-ap-southeast-1-sb"
}

variable state_lock_table_name {
  type    = string
  default = "poc-dev-tfstate-ap-southeast-1-dtb"
}