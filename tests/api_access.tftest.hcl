# SIE GKE Terraform - Kubernetes API access tests
#
# Run with: terraform test -filter=tests/api_access.tftest.hcl
# Uses mock providers, so no cloud credentials are needed.

mock_provider "google" {
  mock_data "google_client_openid_userinfo" {
    defaults = {
      email = "operator@example.com"
    }
  }
}

mock_provider "google-beta" {}
mock_provider "time" {}

variables {
  project_id   = "test-project"
  region       = "us-central1"
  cluster_name = "sie-test"
}

run "rejects_unset_api_access" {
  command = plan

  expect_failures = [var.authorized_networks]
}

run "rejects_ipv4_any_address_without_opt_in" {
  command = plan

  variables {
    authorized_networks = [{ cidr_block = "0.0.0.0/0", display_name = "any" }]
  }

  expect_failures = [var.authorized_networks]
}

run "rejects_ipv6_any_address_without_opt_in" {
  command = plan

  variables {
    authorized_networks = [{ cidr_block = "::/0", display_name = "any" }]
  }

  expect_failures = [var.authorized_networks]
}

run "rejects_split_any_address_without_opt_in" {
  command = plan

  variables {
    authorized_networks = [
      { cidr_block = "0.0.0.0/1", display_name = "low" },
      { cidr_block = "128.0.0.0/1", display_name = "high" },
    ]
  }

  expect_failures = [var.authorized_networks]
}

run "rejects_malformed_range" {
  command = plan

  variables {
    authorized_networks = [{ cidr_block = "203.0.113.10", display_name = "workstation" }]
  }

  expect_failures = [var.authorized_networks]
}

run "rejects_private_endpoint_without_private_nodes" {
  command = plan

  variables {
    enable_private_nodes    = false
    enable_private_endpoint = true
  }

  expect_failures = [var.enable_private_endpoint]
}
