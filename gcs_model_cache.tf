# SIE Model Cache and Payload Store - GCS Bucket
#
# Provisions a single managed GCS bucket that serves both the model cache
# (under `models/`) and the gateway payload store (under `payloads/`).
# Both prefixes are independently IAM-gated by prefix-scoped custom roles
# (see `iam.tf`).
#
# Opt-in via `var.create_model_cache = true`. Operators who already own a
# bucket can keep the BYO path by passing `var.gcs_bucket_name`; the two
# variables are mutually exclusive.

locals {
  # Default location: deployment region. An explicit value beats it.
  effective_model_cache_location = (
    var.model_cache_location != ""
    ? var.model_cache_location
    : var.region
  )

  # Normalize to a single source of truth used by IAM and outputs so the
  # bucket name is referenced exactly once when create_model_cache=true.
  managed_model_cache_bucket = (
    var.create_model_cache
    ? google_storage_bucket.model_cache[0].name
    : null
  )
}

resource "google_storage_bucket" "model_cache" {
  count = var.create_model_cache ? 1 : 0

  # Bucket names are globally unique. Tying the suffix to the project plus
  # cluster avoids collisions for users who run multiple SIE clusters in
  # the same project, and keeps the name deterministic across applies.
  name     = "${var.project_id}-${var.cluster_name}-sie-model-cache"
  project  = var.project_id
  location = local.effective_model_cache_location

  storage_class = var.model_cache_storage_class

  # Uniform bucket-level access disables legacy per-object ACLs and is a
  # prerequisite for IAM Conditions (which we use for prefix scoping).
  uniform_bucket_level_access = true

  # Hard-block public exposure: this bucket holds private model weights
  # and request payloads, both of which must never become reachable from
  # the public internet via an inadvertent ACL or signed URL fallback.
  public_access_prevention = "enforced"

  versioning {
    enabled = var.model_cache_versioning_enabled
  }

  dynamic "encryption" {
    for_each = var.model_cache_kms_key_name != "" ? [1] : []
    content {
      default_kms_key_name = var.model_cache_kms_key_name
    }
  }

  # Lifecycle rules.
  #
  # 1. expire-payloads: GC objects under the `payloads/` prefix after
  #    `var.model_cache_payload_expiration_days` (default 1 day). The
  #    gateway's runtime TTL (`payloadStore.ttlSeconds`, 300s by default)
  #    is the primary GC; this lifecycle rule is the long-tail safety net
  #    for orphans left behind by gateway crashes between PutObject and
  #    queue ack. GCS lifecycle is day-granularity so it cannot replace
  #    the runtime TTL.
  #
  # 2. abort-incomplete-multipart-uploads: GCS uses resumable uploads for
  #    large objects. The `AbortIncompleteMultipartUpload` lifecycle
  #    action does not exist on GCS the way it does on S3, but unfinished
  #    resumable uploads do not produce billable objects until completed,
  #    so this rule is intentionally omitted (matches S3 lifecycle in
  #    behavior, not in literal rule shape).

  lifecycle_rule {
    condition {
      age            = var.model_cache_payload_expiration_days
      matches_prefix = ["payloads/"]
    }
    action {
      type = "Delete"
    }
  }

  labels = local.resource_labels

  # create_model_cache now defaults true, so guard the BYO path: a managed
  # bucket and a caller-supplied gcs_bucket_name are mutually exclusive.
  lifecycle {
    precondition {
      condition     = trimspace(var.gcs_bucket_name) == ""
      error_message = "create_model_cache=true provisions a managed bucket, but gcs_bucket_name (BYO) is also set. These are mutually exclusive: unset gcs_bucket_name, or set create_model_cache=false to use your BYO bucket."
    }
  }
}
