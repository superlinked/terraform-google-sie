# SIE GKE Cluster - Development Example (L4 Spot)
#
# Creates a GKE cluster with GPU nodes. K8s resources (KEDA, Prometheus,
# SIE application) are deployed via Helm after this terraform apply.
#
# See oci://ghcr.io/superlinked/charts/sie-cluster  for the Helm chart.
#
# Features:
#   - 1x L4 GPU spot pool (scale 0-5)
#   - NAP enabled for automatic node provisioning
#   - Workload Identity for GCS access
#   - Artifact Registry for SIE images
#
# Prerequisites:
#   1. GCP project with billing enabled
#   2. GPU quota (check with: gcloud compute regions describe REGION --format='table(quotas.filter(metric:NVIDIA))')
#   3. APIs enabled: container.googleapis.com, compute.googleapis.com
#
# Usage:
#   export TF_VAR_project_id="your-project-id"
#   terraform init
#   terraform plan
#   terraform apply
#
# After apply, deploy K8s resources (batteries-included Helm chart):
#   $(terraform output -raw kubectl_command)
#   helm upgrade --install sie-cluster deploy/helm/sie-cluster \
#     -f values-gke.yaml \
#     --create-namespace -n sie \
#     --set serviceAccount.annotations."iam\.gke\.io/gcp-service-account"="$(terraform output -raw sie_workload_service_account)"
#
# Cleanup:
#   helm uninstall sie-cluster
#   terraform destroy

terraform {
  required_version = "~> 1.14.3"

  # Uncomment to use GCS backend for state
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "sie/gke"
  # }
}

# =============================================================================
# Variables
# =============================================================================

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
  default     = "sie-dev"
}

variable "create_artifact_registry" {
  description = "Whether to create an Artifact Registry for SIE images"
  type        = bool
  default     = true
}

variable "deployer_service_account" {
  description = "Email of the service account running Terraform (optional, for CI/CD)"
  type        = string
  default     = ""
}

# =============================================================================
# SIE GKE Infra Module
# =============================================================================

module "infra" {
  source  = "superlinked/sie/google"
  version = "0.1.8"

  project_id               = var.project_id
  region                   = var.region
  cluster_name             = var.cluster_name
  deployer_service_account = var.deployer_service_account
  deletion_protection      = false # Dev cluster - allow easy cleanup

  # Network
  create_network = true
  network        = "sie-network"
  subnetwork     = "sie-subnet"

  # Private cluster with NAT
  enable_private_nodes = true

  # Node Auto-Provisioning (NAP)
  enable_node_auto_provisioning = true
  nap_max_cpu                   = 100
  nap_max_memory_gb             = 400

  # CPU node pool for system workloads
  cpu_node_pool = {
    machine_type   = "e2-standard-4"
    min_node_count = 1
    max_node_count = 3
  }

  # GPU node pool - L4 for inference
  gpu_node_pools = [
    {
      name            = "l4-spot"
      machine_type    = "g2-standard-8" # 8 vCPU, 32GB RAM, 1x L4
      gpu_type        = "nvidia-l4"
      gpu_count       = 1
      min_node_count  = 0 # Scale to zero when idle
      max_node_count  = 5
      spot            = true # ~60% savings
      local_ssd_count = 1    # 375GB local SSD for model cache
      zones           = ["us-central1-a", "us-central1-b", "us-central1-c"]
      taints = [{
        key    = "nvidia.com/gpu"
        value  = "present"
        effect = "NO_SCHEDULE"
      }]
      labels = {
        "sie.superlinked.com/gpu-type" = "l4"
      }
    }
  ]

  # Workload Identity for GCS access
  enable_workload_identity = true
  sie_namespace            = "sie"
  sie_service_account_name = "sie-server"

  # Artifact Registry for SIE images
  create_artifact_registry = var.create_artifact_registry

  # GKE native logging
  enable_cloud_logging = true

  labels = {
    "environment" = "dev"
    "managed-by"  = "terraform"
  }
}

# =============================================================================
# Outputs
# =============================================================================

output "cluster_name" {
  description = "GKE cluster name"
  value       = module.infra.cluster_name
}

output "kubectl_command" {
  description = "Command to configure kubectl"
  value       = module.infra.kubectl_config_command
}

output "artifact_registry_url" {
  description = "Artifact Registry URL for pushing images"
  value       = module.infra.artifact_registry_url
}

output "workload_identity_annotation" {
  description = "Annotation for Kubernetes service accounts (Workload Identity)"
  value       = module.infra.workload_identity_annotation
}
