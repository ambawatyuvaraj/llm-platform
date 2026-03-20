terraform {

  required_version = ">=1.5.0"

  required_providers {
    # we're using aws free tier 
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}