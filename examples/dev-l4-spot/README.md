# Development Cluster with L4 Spot GPUs

Creates a minimal GKE cluster with a single L4 GPU spot node pool - ideal for development and testing SIE (Search Inference Engine) workloads at low cost.

## What this example creates

| Resource | Configuration |
|----------|---------------|
| GKE cluster | Private nodes, Cloud NAT, Workload Identity, API endpoint restricted to `api_server_authorized_ip_ranges` |
| GPU node pool | 1x NVIDIA L4 per node (g2-standard-8), spot VMs, scale 0-5 |
| CPU node pool | e2-standard-4, scale 1-3 (system workloads) |
| Artifact Registry | Docker repository for SIE images |
| NAP | Node Auto-Provisioning enabled (auto-creates pools as needed) |

**Estimated cost**: ~$0.50/hr when a GPU node is running. $0/hr when scaled to zero (only the GKE management fee applies).

## Usage

The Kubernetes API endpoint accepts only the CIDRs you list. Include the
address the machine running kubectl and Helm uses to reach the Internet.
`203.0.113.10/32` below is a documentation placeholder. The module rejects
documentation ranges, so replace it with your own address.

```bash
export TF_VAR_project_id="your-gcp-project-id"
curl -s https://checkip.amazonaws.com   # your egress address; append /32
export TF_VAR_api_server_authorized_ip_ranges='["203.0.113.10/32"]'

terraform init
terraform plan
terraform apply
```

After apply, deploy SIE via Helm:

```bash
# Configure kubectl
$(terraform output -raw kubectl_command)

# Fetch the overlay from the same SIE release
curl -fsSL -o values-gke.yaml \
  https://raw.githubusercontent.com/superlinked/sie/v0.9.0/deploy/helm/sie-cluster/values-gke.yaml

# Install SIE with its published service and CUDA 12 default worker images
helm upgrade --install sie-cluster oci://ghcr.io/superlinked/charts/sie-cluster \
  --version 0.9.0 -f values-gke.yaml \
  --create-namespace -n sie \
  --set-string "serviceAccount.annotations.iam\\.gke\\.io/gcp-service-account=$(terraform output -raw sie_workload_service_account)" \
  $(terraform output -raw model_cache_helm_args)
```

Chart `0.9.0` selects `v0.9.0` service images and the
`v0.9.0-cuda12-default` worker image. The example pins the Terraform module
release from the Registry, which is versioned independently of SIE. The cache
arguments above also configure the chart's required payload-store bucket.

Chart `0.9.0` has breaking changes for existing releases: NATS authentication
is on by default, the GKE values file no longer enables the gateway Ingress,
and `helm upgrade --reuse-values` fails to render. Before upgrading a release
installed from an earlier chart, follow
[Upgrading to SIE 0.9.0](../../README.md#upgrading-to-sie-090) in the module
README.

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `project_id` | _(required)_ | Your GCP project ID |
| `region` | `us-central1` | GCP region |
| `cluster_name` | `sie-dev` | Cluster name |
| `create_artifact_registry` | `true` | Create a Docker registry for SIE images |
| `deployer_service_account` | `""` | Service account email (for CI/CD; optional for interactive use) |
| `api_server_authorized_ip_ranges` | _(required)_ | CIDRs allowed to reach the Kubernetes API, such as `["203.0.113.10/32"]`; passed to the module's `authorized_networks` |

## Outputs

| Output | Description |
|--------|-------------|
| `cluster_name` | GKE cluster name |
| `kubectl_command` | Run this to configure kubectl |
| `artifact_registry_url` | URL for pushing Docker images |
| `artifact_registry_server_repository_url` | Push target for `sie-server` images |
| `artifact_registry_gateway_repository_url` | Push target for `sie-gateway` images |
| `artifact_registry_config_repository_url` | Push target for `sie-config` images |
| `sie_workload_service_account` | GCP service account email for the Helm Workload Identity annotation |
| `workload_identity_annotation` | Precomposed `iam.gke.io/gcp-service-account=email` pair |
| `model_cache_helm_args` | Helm arguments for the managed model cache and payload store |

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
