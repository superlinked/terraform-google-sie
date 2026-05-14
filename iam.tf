# SIE GKE Cluster - IAM Configuration
#
# Service accounts and IAM bindings for GKE nodes and SIE workloads.

# =============================================================================
# Service Accounts
# =============================================================================

# Service account for GKE nodes
resource "google_service_account" "gke_nodes" {
  project      = var.project_id
  account_id   = local.names.nodes_sa
  display_name = "GKE Nodes Service Account for ${var.cluster_name}"
}

# Minimal permissions for GKE nodes
resource "google_project_iam_member" "gke_nodes_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Artifact Registry reader (for pulling SIE images) - project level
resource "google_project_iam_member" "gke_nodes_artifact_registry" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Allow deployer SA to use node SA (required for creating node pools with a service account)
# Auto-detects when running as a service account (CI/CD) and grants necessary permission
# For interactive use with `gcloud auth login`, the user typically has sufficient permissions
resource "google_service_account_iam_member" "deployer_can_use_node_sa" {
  count = local.deployer_service_account != "" ? 1 : 0

  service_account_id = google_service_account.gke_nodes.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${local.deployer_service_account}"
}

# =============================================================================
# Workload Identity for SIE
# =============================================================================

# GCP service account for SIE workloads (GCS access)
resource "google_service_account" "sie_workload" {
  count = var.enable_workload_identity ? 1 : 0

  project      = var.project_id
  account_id   = local.names.workload_sa
  display_name = "SIE Workload Identity for ${var.cluster_name}"
}

# Wait for the project-level workload identity pool (`PROJECT.svc.id.goog`) to
# become queryable by the IAM API after the cluster comes up. The pool is
# provisioned implicitly when GKE finishes creating the cluster with Workload
# Identity enabled, but propagates a few tens of seconds behind the cluster's
# "ready" signal. Without this wait, the first `terraform apply` on a fresh
# project fails on the binding below with `Error 400: Identity Pool does not
# exist (PROJECT.svc.id.goog)`; a re-apply then succeeds in ~10s.
resource "time_sleep" "wait_for_identity_pool" {
  count = var.enable_workload_identity ? 1 : 0

  depends_on      = [google_container_cluster.primary]
  create_duration = "60s"

  triggers = {
    cluster_id = google_container_cluster.primary.id
  }
}

# Allow K8s service account to impersonate GCP service account.
#
# Explicit `depends_on` is required: the binding references the project-level
# identity pool through `member`, which Terraform cannot infer ordering for.
resource "google_service_account_iam_member" "sie_workload_identity" {
  count = var.enable_workload_identity ? 1 : 0

  service_account_id = google_service_account.sie_workload[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.sie_namespace}/${var.sie_service_account_name}]"

  depends_on = [
    google_container_cluster.primary,
    time_sleep.wait_for_identity_pool,
  ]
}

# GCS bucket access for model cache - BYO bucket path.
#
# Retained for backward compatibility with operators who set
# `var.gcs_bucket_name` to a pre-existing bucket. Grants read-only object
# access bucket-wide because we cannot make IAM Condition assumptions about
# the prefix layout in a BYO bucket. New deployments should prefer the
# managed bucket path (`var.create_model_cache = true`), which grants the
# tighter prefix-scoped custom roles defined below.
resource "google_storage_bucket_iam_member" "sie_gcs_access" {
  count = var.enable_workload_identity && var.gcs_bucket_name != "" ? 1 : 0

  bucket = var.gcs_bucket_name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.sie_workload[0].email}"
}

# =============================================================================
# Managed model-cache bucket - custom IAM roles + prefix-scoped bindings
#
# Two custom roles, bound with IAM Conditions to scope each role's
# permissions to a single top-level prefix in the managed bucket. The
# principle is least-privilege: workers can read weights but not delete
# them, and the gateway can write+delete payload refs but cannot touch
# weights even though they share the bucket.
#
# IAM Conditions on GCS require uniform bucket-level access (set on the
# bucket resource in `gcs_model_cache.tf`). The `resource.name.startsWith`
# expression matches the object resource name format that GCS reports to
# IAM, which is `projects/_/buckets/{bucket}/objects/{path}`.
# =============================================================================

resource "google_project_iam_custom_role" "sie_model_cache_reader" {
  count = var.create_model_cache && var.enable_workload_identity ? 1 : 0

  project = var.project_id
  role_id = replace("${var.project_id}_${var.cluster_name}_sie_model_cache_reader", "-", "_")
  title   = "SIE Model Cache Reader (${var.cluster_name})"
  description = join("", [
    "Read-only access to SIE model weights. Grants get/list on objects ",
    "in the managed model-cache bucket. Bound to the SIE workload service ",
    "account with an IAM Condition scoping the role to the `models/` ",
    "prefix. Created by deploy/terraform/gcp/infra/iam.tf."
  ])
  stage = "GA"
  permissions = [
    "storage.buckets.get",
    "storage.objects.get",
    "storage.objects.list",
  ]
}

resource "google_project_iam_custom_role" "sie_payload_store_writer" {
  count = var.create_model_cache && var.enable_workload_identity ? 1 : 0

  project = var.project_id
  role_id = replace("${var.project_id}_${var.cluster_name}_sie_payload_store_writer", "-", "_")
  title   = "SIE Payload Store Writer (${var.cluster_name})"
  description = join("", [
    "Read/write/delete on gateway payload refs. Grants ",
    "get/create/delete/list on objects in the managed model-cache bucket. ",
    "Bound to the SIE workload service account with an IAM Condition ",
    "scoping the role to the `payloads/` prefix. Created by ",
    "deploy/terraform/gcp/infra/iam.tf."
  ])
  stage = "GA"
  permissions = [
    "storage.objects.create",
    "storage.objects.delete",
    "storage.objects.get",
    "storage.objects.list",
  ]
}

resource "google_storage_bucket_iam_member" "sie_model_cache_reader_binding" {
  count = var.create_model_cache && var.enable_workload_identity ? 1 : 0

  bucket = google_storage_bucket.model_cache[0].name
  role   = google_project_iam_custom_role.sie_model_cache_reader[0].id
  member = "serviceAccount:${google_service_account.sie_workload[0].email}"

  condition {
    title       = "ModelsPrefixOnly"
    description = "Restricts read access to objects under the `models/` prefix."
    expression  = "resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.model_cache[0].name}/objects/models/\")"
  }
}

resource "google_storage_bucket_iam_member" "sie_payload_store_writer_binding" {
  count = var.create_model_cache && var.enable_workload_identity ? 1 : 0

  bucket = google_storage_bucket.model_cache[0].name
  role   = google_project_iam_custom_role.sie_payload_store_writer[0].id
  member = "serviceAccount:${google_service_account.sie_workload[0].email}"

  condition {
    title       = "PayloadsPrefixOnly"
    description = "Restricts read/write/delete access to objects under the `payloads/` prefix."
    expression  = "resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.model_cache[0].name}/objects/payloads/\")"
  }
}
