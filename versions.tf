terraform {
  required_version = "~> 1.14.3"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.25.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.25.0"
    }
  }
}
