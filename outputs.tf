# SIE GKE Cluster - Infrastructure Outputs
#
# Outputs consumed by the sie-cluster Helm chart and external tooling.

# =============================================================================
# Cluster Connection
# =============================================================================

output "cluster_endpoint" {
  description = "GKE cluster API endpoint"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate (base64 encoded)"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.primary.name
}

output "cluster_id" {
  description = "GKE cluster ID"
  value       = google_container_cluster.primary.id
}

output "cluster_location" {
  description = "GKE cluster location (region)"
  value       = google_container_cluster.primary.location
}

# =============================================================================
# Project and Region
# =============================================================================

output "project_id" {
  description = "GCP project ID"
  value       = var.project_id
}

output "region" {
  description = "GCP region"
  value       = var.region
}

# =============================================================================
# Service Accounts
# =============================================================================

output "gke_nodes_service_account" {
  description = "Service account email for GKE nodes"
  value       = google_service_account.gke_nodes.email
}

output "sie_workload_service_account" {
  description = "Service account email for SIE workloads (Workload Identity)"
  value       = var.enable_workload_identity ? google_service_account.sie_workload[0].email : null
}

# =============================================================================
# Network Information
# =============================================================================

output "network_name" {
  description = "VPC network name"
  value       = var.create_network ? local.names.network : var.network
}

output "subnetwork_name" {
  description = "Subnetwork name"
  value       = var.create_network ? local.names.subnet : var.subnetwork
}

# =============================================================================
# Model Cache and Payload Store (managed bucket)
#
# Populated only when `create_model_cache = true`. The `model_cache_helm_args`
# output is the recommended way to pass these values to Helm so the chart's
# auto-derivation kicks in and points the payload store at the same bucket
# under the sibling `payloads/` prefix.
# =============================================================================

output "model_cache_bucket_name" {
  description = "Name of the managed GCS model-cache bucket. Null when create_model_cache=false."
  value       = local.managed_model_cache_bucket
}

output "model_cache_bucket_url" {
  description = <<-EOT
    GCS URL of the managed model-cache bucket including the `/models`
    prefix. Pass to Helm as `workers.common.clusterCache.url`, and to
    `sie-admin cache populate` as `--target`. Null when
    `create_model_cache=false`.
  EOT
  value       = try("gs://${local.managed_model_cache_bucket}/models", null)
}

output "payload_store_url" {
  description = <<-EOT
    GCS URL of the gateway payload store (managed model-cache bucket
    under the `/payloads` prefix). Exposed for visibility; the Helm chart
    auto-derives this from `workers.common.clusterCache.url` so most
    operators do not need to set it directly. Null when
    `create_model_cache=false`.
  EOT
  value       = try("gs://${local.managed_model_cache_bucket}/payloads", null)
}

output "model_cache_helm_args" {
  description = <<-EOT
    Helm --set arguments to wire the managed model-cache bucket into the
    sie-cluster chart. The chart's auto-derivation produces a payload-
    store URL at the `payloads/` prefix of the same bucket once
    `clusterCache.url` is set. Empty when `create_model_cache=false`.
  EOT
  value = try(
    join(" ", [
      "--set workers.common.clusterCache.enabled=true",
      "--set workers.common.clusterCache.url=gs://${local.managed_model_cache_bucket}/models",
    ]),
    ""
  )
}

# =============================================================================
# Artifact Registry
# =============================================================================

output "artifact_registry_url" {
  description = "Artifact Registry URL for SIE images"
  value       = var.create_artifact_registry ? "${var.artifact_registry_location != "" ? var.artifact_registry_location : var.region}-docker.pkg.dev/${var.project_id}/${local.names.registry}" : null
}

# =============================================================================
# Node Pools
# =============================================================================

output "cpu_node_pool_name" {
  description = "CPU node pool name"
  value       = google_container_node_pool.cpu.name
}

output "gpu_node_pool_names" {
  description = "GPU node pool names"
  value       = [for pool in google_container_node_pool.gpu : pool.name]
}

# =============================================================================
# GPU Pool Configuration (for Helm chart worker pools)
# =============================================================================

output "gpu_node_pools" {
  description = "GPU node pool configurations (for Helm chart worker pool configuration)"
  value       = var.gpu_node_pools
}

# =============================================================================
# kubectl Configuration
# =============================================================================

output "kubectl_config_command" {
  description = "Command to configure kubectl for this cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.region} --project ${var.project_id}"
}

# =============================================================================
# Workload Identity Annotation
# =============================================================================

output "workload_identity_annotation" {
  description = "Annotation to add to K8s service account for Workload Identity"
  value       = var.enable_workload_identity ? "iam.gke.io/gcp-service-account=${google_service_account.sie_workload[0].email}" : null
}

# =============================================================================
# Kubernetes Connection Details (for external providers)
# =============================================================================

output "kubernetes_host" {
  description = "Kubernetes API server host"
  value       = "https://${google_container_cluster.primary.endpoint}"
  sensitive   = true
}

output "kubernetes_token" {
  description = "Kubernetes auth token (from gcloud)"
  value       = data.google_client_config.current.access_token
  sensitive   = true
}

# =============================================================================
# Terraform-to-Helm Contract
# =============================================================================
#
# The sie-cluster Helm chart (oci://ghcr.io/superlinked/charts/sie-cluster ) depends on the
# following infra outputs. Pass them as Helm values after `terraform output`:
#
#   cluster_endpoint          -> not needed by Helm (kubectl handles this)
#   cluster_name              -> informational
#   project_id                -> .global.gcp.projectId
#   region                    -> .global.gcp.region
#   sie_workload_service_account -> .serviceAccount.annotations
#                                  (iam.gke.io/gcp-service-account)
#   workload_identity_annotation -> direct annotation value for service account
#   artifact_registry_url     -> image registry base URL
#   gpu_node_pools            -> .workers[*].nodeSelector / tolerations
#                                (use labels and taints from pool configs)
#   kubectl_config_command    -> run before `helm install` to configure kubectl
#
# Typical deploy sequence after `terraform apply`:
#   $(terraform output -raw kubectl_config_command)
#   helm upgrade --install sie-cluster deploy/helm/sie-cluster \
#     --set global.workloadIdentityAnnotation="$(terraform output -raw workload_identity_annotation)" \
#     --set global.artifactRegistryUrl="$(terraform output -raw artifact_registry_url)"
