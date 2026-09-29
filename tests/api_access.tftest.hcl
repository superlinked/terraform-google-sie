# SIE GKE Terraform - Kubernetes API access tests
#
# Run with: terraform test -filter=tests/api_access.tftest.hcl
# Uses mock providers, so no cloud credentials are needed.

mock_provider "google" {
  override_during = plan

  mock_data "google_client_openid_userinfo" {
    defaults = {
      email = "operator@example.com"
    }
  }
}

mock_provider "google-beta" {
  override_during = plan
}

mock_provider "time" {}

variables {
  project_id   = "test-project"
  region       = "us-central1"
  cluster_name = "sie-test"
}

# =============================================================================
# Rejected configurations
# =============================================================================

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

run "rejects_aggregate_above_one_slash8_without_opt_in" {
  command = plan

  variables {
    authorized_networks = [
      { cidr_block = "11.0.0.0/8", display_name = "a" },
      { cidr_block = "12.0.0.0/8", display_name = "b" },
    ]
  }

  expect_failures = [var.authorized_networks]
}

run "rejects_ipv6_any_address" {
  command = plan

  variables {
    authorized_networks = [{ cidr_block = "::/0", display_name = "any" }]
  }

  expect_failures = [var.authorized_networks]
}

run "rejects_ipv6_range_for_ipv4_cluster" {
  command = plan

  variables {
    authorized_networks = [{ cidr_block = "::/16", display_name = "mapped" }]
  }

  expect_failures = [var.authorized_networks]
}

run "rejects_malformed_range" {
  command = plan

  variables {
    authorized_networks = [{ cidr_block = "8.8.8.8", display_name = "workstation" }]
  }

  expect_failures = [var.authorized_networks]
}

run "rejects_documentation_placeholder" {
  command = plan

  variables {
    authorized_networks = [{ cidr_block = "203.0.113.10/32", display_name = "placeholder" }]
  }

  expect_failures = [var.authorized_networks]
}

run "rejects_more_than_100_networks" {
  command = plan

  variables {
    authorized_networks = [for i in range(101) : { cidr_block = cidrsubnet("8.0.0.0/8", 16, i), display_name = "n${i}" }]
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

# =============================================================================
# Accepted configurations
# =============================================================================

run "restricts_public_endpoint_to_authorized_networks" {
  command = plan

  variables {
    authorized_networks = [{ cidr_block = "8.8.8.8/32", display_name = "workstation" }]
  }

  assert {
    condition     = google_container_cluster.primary.private_cluster_config[0].enable_private_endpoint == false
    error_message = "An authorized-networks allowlist should keep the public endpoint enabled"
  }

  assert {
    condition = (
      length(google_container_cluster.primary.master_authorized_networks_config) == 1
      && google_container_cluster.primary.master_authorized_networks_config[0].gcp_public_cidrs_access_enabled == false
      && [for block in google_container_cluster.primary.master_authorized_networks_config[0].cidr_blocks : block.cidr_block] == ["8.8.8.8/32"]
    )
    error_message = "Master authorized networks should admit only the allowlisted range and no Google Cloud public addresses"
  }

  assert {
    condition     = !endswith(output.kubectl_config_command, " --internal-ip")
    error_message = "The kubectl command should use the public endpoint"
  }
}

run "accepts_networks_totalling_one_slash8" {
  command = plan

  variables {
    authorized_networks = [
      { cidr_block = "11.0.0.0/9", display_name = "a" },
      { cidr_block = "11.128.0.0/9", display_name = "b" },
    ]
  }

  assert {
    condition     = length(google_container_cluster.primary.master_authorized_networks_config[0].cidr_blocks) == 2
    error_message = "Authorized networks covering exactly one /8 should be accepted"
  }
}

run "private_endpoint_disables_public_endpoint" {
  command = plan

  variables {
    enable_private_endpoint = true
  }

  assert {
    condition     = google_container_cluster.primary.private_cluster_config[0].enable_private_endpoint == true
    error_message = "enable_private_endpoint should disable the public endpoint"
  }

  assert {
    condition = (
      length(google_container_cluster.primary.master_authorized_networks_config) == 1
      && length(google_container_cluster.primary.master_authorized_networks_config[0].cidr_blocks) == 0
      && google_container_cluster.primary.master_authorized_networks_config[0].gcp_public_cidrs_access_enabled == false
    )
    error_message = "Master authorized networks should stay managed with no external ranges"
  }

  assert {
    condition     = endswith(output.kubectl_config_command, " --internal-ip")
    error_message = "The kubectl command should use the private endpoint"
  }
}

run "private_endpoint_enforces_listed_networks" {
  command = plan

  variables {
    enable_private_endpoint = true
    authorized_networks     = [{ cidr_block = "10.8.0.0/16", display_name = "vpn" }]
  }

  assert {
    condition     = google_container_cluster.primary.master_authorized_networks_config[0].private_endpoint_enforcement_enabled == true
    error_message = "Authorized networks should be enforced on the private endpoint in private-endpoint mode"
  }
}

run "opt_in_leaves_authorized_networks_unmanaged" {
  command = plan

  variables {
    allow_public_api_server = true
  }

  assert {
    condition     = length(google_container_cluster.primary.master_authorized_networks_config) == 0
    error_message = "allow_public_api_server with no networks should leave master authorized networks unmanaged"
  }
}

run "opt_in_accepts_any_address_network" {
  command = plan

  variables {
    allow_public_api_server = true
    authorized_networks     = [{ cidr_block = "0.0.0.0/0", display_name = "any" }]
  }

  assert {
    condition     = [for block in google_container_cluster.primary.master_authorized_networks_config[0].cidr_blocks : block.cidr_block] == ["0.0.0.0/0"]
    error_message = "allow_public_api_server should accept 0.0.0.0/0 in authorized_networks"
  }
}
