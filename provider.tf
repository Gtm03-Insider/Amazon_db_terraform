# Provider configuration for AWS. Reads `var.region` and optional `var.aws_profile`.
provider "aws" {
  region = var.region
  # Optional: use a specific AWS CLI profile
  # profile = var.aws_profile
}
# terraform {
#   required_version = ">= 1.0"
#   required_providers {
#     aws = {
#       source  = "hashicorp/aws"
#       version = ">= 4.0"
#     }
#   }
# }
