terraform {
  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "2.3.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "4.57.0"
    }
  }

  required_version = "~> 1.3"
}
