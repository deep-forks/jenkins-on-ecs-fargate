terraform {
  required_version = ">= 0.13"
  backend "s3" {
    bucket = "genpact-poc-dev-tfstate-ap-south-1-sb"
    key    = "jenkins/infratfstate"
    dynamodb_table = "genpact-poc-dev-tfstate-ap-south-1-dtb"
    region = "ap-south-1"
    encrypt = true
  }
}

provider "aws" {}
