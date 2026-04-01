# Development Cluster with L4 Spot GPUs

Creates a minimal GKE cluster with a single L4 GPU spot node pool — ideal for development and testing SIE (Search Inference Engine) workloads at low cost.

## What this example creates

| Resource | Configuration |
|----------|---------------|
| GKE cluster | Private nodes, Cloud NAT, Workload Identity |
| GPU node pool | 1x NVIDIA L4 per node (g2-standard-8), spot VMs, scale 0-5 |
| CPU node pool | e2-standard-4, scale 1-3 (system workloads) |
| Artifact Registry | Docker repository for SIE images |
| NAP | Node Auto-Provisioning enabled (auto-creates pools as needed) |

**Estimated cost**: ~$0.50/hr when a GPU node is running. $0/hr when scaled to zero (only the GKE management fee applies).

## Usage

```bash
export TF_VAR_project_id="your-gcp-project-id"

terraform init
terraform plan
terraform apply
```

After apply, deploy SIE via Helm:

```bash
# Configure kubectl
$(terraform output -raw kubectl_command)

# Install SIE (router, workers, KEDA, Prometheus, Grafana)
helm upgrade --install sie-cluster oci://ghcr.io/superlinked/charts/sie-cluster --version 0.1.8 \
  -f values-gke.yaml \
  --create-namespace -n sie \
  --set serviceAccount.annotations."iam\.gke\.io/gcp-service-account"="$(terraform output -raw workload_identity_annotation)"
```

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `project_id` | — (required) | Your GCP project ID |
| `region` | `us-central1` | GCP region |
| `cluster_name` | `sie-dev` | Cluster name |
| `create_artifact_registry` | `true` | Create a Docker registry for SIE images |
| `deployer_service_account` | `""` | Service account email (for CI/CD; optional for interactive use) |

## Outputs

| Output | Description |
|--------|-------------|
| `cluster_name` | GKE cluster name |
| `kubectl_command` | Run this to configure kubectl |
| `artifact_registry_url` | URL for pushing Docker images |
| `workload_identity_annotation` | Annotation for Helm service account |

## Customizing

**Change region:**

```bash
export TF_VAR_region="europe-west4"
```

**Use on-demand instead of spot (more reliable, higher cost):**

Override `gpu_node_pools` in a `terraform.tfvars` file:

```hcl
gpu_node_pools = [
  {
    name           = "l4-ondemand"
    machine_type   = "g2-standard-8"
    gpu_type       = "nvidia-l4"
    gpu_count      = 1
    min_node_count = 0
    max_node_count = 5
    spot           = false
  }
]
```

## Prerequisites

1. GCP project with billing enabled
2. GPU quota for `nvidia-l4` in your region (check: `gcloud compute regions describe REGION --format="table(quotas.filter(metric:NVIDIA))"`)
3. APIs enabled: `container.googleapis.com`, `compute.googleapis.com`

## Cleanup

```bash
terraform destroy
```
