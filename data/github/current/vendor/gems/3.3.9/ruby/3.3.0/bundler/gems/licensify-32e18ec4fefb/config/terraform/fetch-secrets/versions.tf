terraform {
  required_version = ">= 1.0, < 1.4.5"

  required_providers {
    octovault = {
      source  = "terraform.githubapp.com/shared-providers/octovault"
      version = "~> 2.0"
    }
  }
}
