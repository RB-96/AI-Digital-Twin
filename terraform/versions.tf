terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# provider "aws" {
#   region = "ap-southeast-2"
# }

# Kept temporarily — required to destroy existing ACM state entries; remove after next apply
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}