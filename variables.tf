# SIE GKE Cluster - Infrastructure Variables
#
# Variables for GCP-only resources (no K8s/Helm configuration).

# =============================================================================
# Required Variables
# =============================================================================

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for the cluster (e.g., us-central1, europe-west4)"
  type        = string
}

variable "deployer_service_account" {
  description = "Email of the service account running Terraform (for granting iam.serviceAccountUser on node SA). If empty, uses project editors."
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
  default     = "sie-cluster"
}

variable "deletion_protection" {
  description = "Enable deletion protection for the cluster (set to false for dev/test)"
  type        = bool
  default     = true
}

# =============================================================================
# Network Configuration
# =============================================================================

variable "network" {
  description = "VPC network name (created if create_network=true)"
  type        = string
  default     = "sie-network"
}

variable "subnetwork" {
  description = "Subnetwork name (created if create_network=true)"
  type        = string
  default     = "sie-subnet"
}

variable "create_network" {
  description = "Create VPC network and subnetwork (set false to use existing)"
  type        = bool
  default     = true
}

variable "subnet_cidr" {
  description = "CIDR range for the subnetwork"
  type        = string
  default     = "10.0.0.0/20"
}

variable "pods_cidr" {
  description = "Secondary CIDR range for pods"
  type        = string
  default     = "10.1.0.0/16"
}

variable "services_cidr" {
  description = "Secondary CIDR range for services"
  type        = string
  default     = "10.2.0.0/20"
}

# =============================================================================
# Cluster Configuration
# =============================================================================

variable "kubernetes_version" {
  description = "Kubernetes version (null = latest available)"
  type        = string
  default     = null
}

variable "release_channel" {
  description = "GKE release channel: RAPID, REGULAR, STABLE, or UNSPECIFIED"
  type        = string
  default     = "REGULAR"
}

variable "enable_private_nodes" {
  description = "Enable private nodes (no public IPs on nodes)"
  type        = bool
  default     = true
}

variable "master_ipv4_cidr_block" {
  description = "CIDR block for the master network (private cluster)"
  type        = string
  default     = "172.16.0.0/28"
}

variable "authorized_networks" {
  description = "CIDR blocks authorized to access the cluster master"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

# =============================================================================
# Node Pool Auto-Provisioning (NAP)
# =============================================================================

variable "enable_node_auto_provisioning" {
  description = "Enable cluster autoscaler node auto-provisioning"
  type        = bool
  default     = true
}

variable "nap_min_cpu" {
  description = "Minimum total CPU cores for NAP"
  type        = number
  default     = 0
}

variable "nap_max_cpu" {
  description = "Maximum total CPU cores for NAP"
  type        = number
  default     = 1000
}

variable "nap_min_memory_gb" {
  description = "Minimum total memory (GB) for NAP"
  type        = number
  default     = 0
}

variable "nap_max_memory_gb" {
  description = "Maximum total memory (GB) for NAP"
  type        = number
  default     = 4000
}

# =============================================================================
# GPU Node Pools
# =============================================================================

variable "gpu_node_pools" {
  description = "GPU node pool configurations"
  type = list(object({
    name            = string
    machine_type    = string
    gpu_type        = string # nvidia-l4, nvidia-tesla-a100, nvidia-tesla-t4, etc.
    gpu_count       = number
    min_node_count  = number
    max_node_count  = number
    disk_size_gb    = optional(number, 100)
    disk_type       = optional(string, "pd-ssd")
    local_ssd_count = optional(number, 0)
    spot            = optional(bool, false)
    zones           = optional(list(string), []) # Empty = all zones in region
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    labels = optional(map(string), {})
  }))
  default = [
    {
      name           = "l4-pool"
      machine_type   = "g2-standard-8" # 8 vCPU, 32GB RAM
      gpu_type       = "nvidia-l4"
      gpu_count      = 1
      min_node_count = 1
      max_node_count = 10
      spot           = true
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

  validation {
    condition = alltrue([
      for pool in var.gpu_node_pools : alltrue([
        for zone in pool.zones : startswith(zone, var.region)
      ])
    ])
    error_message = "All GPU node pool zones must belong to the configured region (var.region). For example, if region is \"us-west4\", zones must be \"us-west4-a\", \"us-west4-b\", etc."
  }
}

# =============================================================================
# CPU Node Pool (for system workloads)
# =============================================================================

variable "cpu_node_pool" {
  description = "CPU node pool for system workloads (kube-system, monitoring, etc.)"
  type = object({
    machine_type    = string
    min_node_count  = number
    max_node_count  = number
    disk_size_gb    = optional(number, 50)
    disk_type       = optional(string, "pd-standard")
    local_ssd_count = optional(number, 0)
    spot            = optional(bool, false)
  })
  default = {
    machine_type   = "e2-standard-4"
    min_node_count = 1
    max_node_count = 5
  }
}

# =============================================================================
# Kubelet Log Retention
# =============================================================================

variable "kubelet_container_log_max_size" {
  description = "Maximum size of a single kubelet-managed container log file before rotation. Kubelet rotates by size/files, not wall-clock retention."
  type        = string
  default     = "20Mi"

  validation {
    condition     = can(regex("^[1-9][0-9]*(Ei|Pi|Ti|Gi|Mi|Ki|E|P|T|G|M|K)?$", var.kubelet_container_log_max_size))
    error_message = "kubelet_container_log_max_size must be a positive whole-number Kubernetes quantity such as 20Mi."
  }
}

variable "kubelet_container_log_max_files" {
  description = "Maximum number of rotated kubelet-managed container log files to retain per container."
  type        = number
  default     = 30

  validation {
    condition     = var.kubelet_container_log_max_files >= 2 && floor(var.kubelet_container_log_max_files) == var.kubelet_container_log_max_files
    error_message = "kubelet_container_log_max_files must be an integer at least 2."
  }
}

# =============================================================================
# Workload Identity
# =============================================================================

variable "enable_workload_identity" {
  description = "Enable Workload Identity for GCS/S3 access"
  type        = bool
  default     = true
}

variable "sie_service_account_name" {
  description = "Name of the K8s service account for SIE workloads"
  type        = string
  default     = "sie-server"
}

variable "sie_namespace" {
  description = "Kubernetes namespace for SIE workloads"
  type        = string
  default     = "sie"
}

variable "gcs_bucket_name" {
  description = <<-EOT
    Name of a pre-existing GCS bucket to grant the SIE workload identity read
    access to under the conventional `models/` prefix. Use this for BYO-bucket
    deployments. Leave empty and set `create_model_cache = true` to have the
    module provision a managed bucket with prefix-scoped custom IAM roles
    (recommended for new clusters).
  EOT
  type        = string
  default     = ""
}

# =============================================================================
# Model cache + payload store
#
# When `create_model_cache = true` the module provisions a single GCS bucket
# that serves two co-tenant workloads at sibling top-level prefixes:
#
#   gs://<bucket>/models/...    Model weights, populated by `sie-admin cache
#                               populate` and read by SIE workers at startup.
#                               Long-lived; no lifecycle expiration.
#
#   gs://<bucket>/payloads/...  Large work-item payloads (images, long
#                               documents) that exceed the in-band 1MiB
#                               NATS message budget. Written by sie-gateway
#                               on each request and read once by a worker.
#                               Garbage-collected by the runtime TTL (300s
#                               by default) and by a bucket lifecycle rule
#                               (`age = 1` day) for any orphans.
#
# Two custom IAM roles bound to the workload service account, each gated by
# an IAM Condition that scopes its permissions to its prefix:
#
#   {project}-{cluster}-sie-model-cache-reader  read on  models/*
#   {project}-{cluster}-sie-payload-store-writer  read+create+delete on  payloads/*
#
# This is least-privilege: the workload identity can read weights but cannot
# delete or overwrite them, and can write payloads but cannot touch weights.
# See `gcs_model_cache.tf` and `iam.tf` for the resource definitions.
# =============================================================================

variable "create_model_cache" {
  description = <<-EOT
    Create a managed GCS bucket that serves as both the model cache (under
    `models/`) and the gateway payload store (under `payloads/`). When true,
    the module also creates two prefix-scoped custom IAM roles and binds
    them to the SIE workload service account. Leave false (default) and set
    `gcs_bucket_name` to keep BYO-bucket behavior.
  EOT
  type        = bool
  default     = false
}

variable "model_cache_location" {
  description = <<-EOT
    Location for the managed model-cache bucket. Accepts any GCS location
    string: a region (`us-central1`), a dual-region (`nam4`), or a
    multi-region (`US`). Defaults to the deployment region for lowest
    egress to the cluster. Only used when `create_model_cache = true`.
  EOT
  type        = string
  default     = ""
}

variable "model_cache_storage_class" {
  description = <<-EOT
    Default storage class for objects in the managed model-cache bucket.
    `STANDARD` is the right choice for typical SIE workloads (model
    weights read on every cold-start, payloads read seconds after write).
    Only used when `create_model_cache = true`.
  EOT
  type        = string
  default     = "STANDARD"
}

variable "model_cache_versioning_enabled" {
  description = <<-EOT
    Enable object versioning on the managed model-cache bucket. Off by
    default; the cache layout is content-addressable and versioning adds
    storage cost with no rollback value for the payload-store prefix.
    Only used when `create_model_cache = true`.
  EOT
  type        = bool
  default     = false
}

variable "model_cache_kms_key_name" {
  description = <<-EOT
    Fully qualified Cloud KMS key resource name
    (`projects/.../locations/.../keyRings/.../cryptoKeys/...`) for CMEK
    encryption of objects in the managed model-cache bucket. Leave empty
    to use Google-managed encryption keys. Only used when
    `create_model_cache = true`.
  EOT
  type        = string
  default     = ""
}

variable "model_cache_payload_expiration_days" {
  description = <<-EOT
    Lifecycle expiration (in days) for objects under the `payloads/`
    prefix. The runtime TTL on the gateway is the primary GC mechanism
    (default 300s); this bucket lifecycle rule is the long-tail safety
    net for orphans left behind by gateway crashes between PutObject and
    queue ack. Day granularity is a GCS lifecycle limit. Only used when
    `create_model_cache = true`.
  EOT
  type        = number
  default     = 1
}

# =============================================================================
# Artifact Registry
# =============================================================================

variable "artifact_registry_location" {
  description = "Location for Artifact Registry (defaults to region)"
  type        = string
  default     = ""
}

variable "create_artifact_registry" {
  description = "Create Artifact Registry repository for SIE images"
  type        = bool
  default     = true
}

# =============================================================================
# Observability (GKE Native)
# =============================================================================

variable "enable_managed_prometheus" {
  description = "Enable GKE Managed Prometheus (for GCP Console metrics)"
  type        = bool
  default     = false
}

variable "enable_cloud_logging" {
  description = "Enable Cloud Logging for cluster"
  type        = bool
  default     = true
}

# =============================================================================
# Labels & Tags
# =============================================================================

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    "managed-by" = "terraform"
    "app"        = "sie"
  }
}
