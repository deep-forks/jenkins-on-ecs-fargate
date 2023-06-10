terraform {
  required_version = ">= 0.13"
  backend "s3" {
    bucket         = "poc-dev-tfstate-ap-south-1-sb"
    key            = "jenkins/infratfstate"
    dynamodb_table = "poc-dev-tfstate-ap-south-1-dtb"
    region         = "ap-southeast-1"
  }
}

provider "aws" {}
