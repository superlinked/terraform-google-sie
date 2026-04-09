# SIE GKE Terraform Module

One command to get a GPU-ready GKE cluster for [SIE](https://github.com/superlinked/sie) (Search Inference Engine). The module creates everything you need — VPC, GKE, GPU node pools, container registry, observability — so you can focus on running inference, not managing infrastructure.

- GPU node pools with KEDA autoscaling (scale-to-zero)
- Prometheus/Grafana observability stack
- Workload Identity for GCS access
- NATS-based config distribution for runtime model management

## What you get

- **GKE cluster** with VPC-native networking, private nodes, and Cloud NAT
- **GPU node pools** — L4, T4, A100, or A100-80GB, with automatic driver installation
- **Scale-to-zero** — GPU nodes scale down to zero when idle, so you only pay when running inference
- **Node Auto-Provisioning (NAP)** — GKE automatically creates node pools to fit pending workloads
- **Artifact Registry** — private Docker registry with automatic cleanup policies for dev images
- **Workload Identity** — pods authenticate to GCP without service account keys
- **Observability-ready** — outputs for Prometheus, Grafana, and KEDA integration via the SIE Helm chart
- **Optional SIE application** — deploy the full SIE stack (router, workers, KEDA, Prometheus) via Helm
- **Optional NATS config distribution** — runtime model management with persistent config store (GCS-backed)
- **Optional ingress + auth** — ingress-nginx with oauth2-proxy or static token auth

## Module structure

The Terraform code is split into two layers:

| Layer | Path | What it creates |
|-------|------|-----------------|
| **Infrastructure** | `infra/` | GCP resources only: VPC, GKE cluster, node pools, IAM, Artifact Registry, GCS buckets. Can be applied without a running cluster. |
| **Application** | Root module + Helm chart | Kubernetes resources: KEDA, Prometheus, Grafana, Loki, SIE router/workers, NATS. Requires a running cluster. |

Examples in `examples/` use the `infra/` submodule directly and deploy K8s resources via the [sie-cluster Helm chart](../../helm/sie-cluster/).

## Quick start

```bash
cd examples/dev-l4-spot
export TF_VAR_project_id="your-project-id"
terraform init
terraform plan
terraform apply
```

After apply, configure kubectl and deploy SIE via the Helm chart:

```bash
# Point kubectl at the new cluster
$(terraform output -raw kubectl_command)

# Deploy SIE (router, workers, KEDA, Prometheus, Grafana)
helm upgrade --install sie-cluster ../../deploy/helm/sie-cluster \
  -f ../../deploy/helm/sie-cluster/values-gke.yaml \
  --create-namespace -n sie \
  --set serviceAccount.annotations."iam\.gke\.io/gcp-service-account"="$(terraform output -raw workload_identity_annotation)"
```

## Examples

| Example | GPU | Description |
|---------|-----|-------------|
| [`dev-l4-spot`](examples/dev-l4-spot/) | L4 (g2-standard-8) | Spot instances, scale 0-5 nodes, minimal cost for development |
| [`production`](examples/production/) | L4 + A100 | Multi-tier GPU pools, on-demand + spot, HA CPU pool, STABLE release channel |
| [`eval-eu`](examples/eval-eu/) | L4 + A100 | Europe (europe-west4), spot instances, static token auth |
| [`eval-matrix`](examples/eval-matrix/) | L4 | Matrix evaluation cluster, up to 16 GPU nodes for parallel model evaluation |

## Prerequisites

1. **GCP project** with billing enabled
2. **GPU quota** in your target region — check with: `gcloud compute regions describe REGION --format="table(quotas.filter(metric:NVIDIA))"`. Request increases at [IAM & Admin > Quotas](https://console.cloud.google.com/iam-admin/quotas).
3. **APIs enabled**: `container.googleapis.com`, `compute.googleapis.com`, `artifactregistry.googleapis.com`
4. **Terraform** >= 1.14

### Bootstrap (CI/CD)

For CI/CD pipelines, create a deployer service account with the required IAM roles:

```bash
cd bootstrap
export TF_VAR_project_id="your-project-id"
terraform init
terraform apply
```

This creates a service account with the minimum roles needed to deploy SIE infrastructure. See [`bootstrap/main.tf`](bootstrap/main.tf) for details.

## Variables

### Required

| Variable | Description |
|----------|-------------|
| `project_id` | GCP project ID |
| `region` | GCP region (e.g., `us-central1`, `europe-west4`) |

### Cluster

| Variable | Default | Description |
|----------|---------|-------------|
| `cluster_name` | `sie-cluster` | GKE cluster name |
| `deletion_protection` | `true` | Prevent accidental deletion (set `false` for dev) |
| `kubernetes_version` | `null` (latest) | Pin Kubernetes version, or let GKE manage it |
| `release_channel` | `REGULAR` | `RAPID`, `REGULAR`, `STABLE`, or `UNSPECIFIED` |
| `deployer_service_account` | `""` | Email of the SA running Terraform (auto-detected in CI/CD) |

### GPU configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `gpu_node_pools` | 1x L4 spot pool | List of GPU node pool configurations (see below) |
| `cpu_node_pool` | e2-standard-4 | CPU pool for system workloads (kube-system, monitoring) |

Each entry in `gpu_node_pools` supports:

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `name` | yes | -- | Pool name (e.g., `l4-spot`) |
| `machine_type` | yes | -- | GCE machine type |
| `gpu_type` | yes | -- | Accelerator type |
| `gpu_count` | yes | -- | GPUs per node |
| `min_node_count` | yes | -- | Minimum nodes (0 = scale-to-zero) |
| `max_node_count` | yes | -- | Maximum nodes |
| `spot` | no | `false` | Use spot VMs (~60-91% savings) |
| `disk_size_gb` | no | `100` | Boot disk size |
| `disk_type` | no | `pd-ssd` | Boot disk type |
| `local_ssd_count` | no | `0` | NVMe local SSDs for model cache |
| `zones` | no | all | Restrict to specific zones |
| `taints` | no | `[]` | Kubernetes taints for GPU isolation |
| `labels` | no | `{}` | Additional node labels |

**GPU machine cheat sheet:**

| GPU | Machine Type | VRAM | Approx. spot/hr | Best for |
|-----|-------------|------|------------------|----------|
| L4 | `g2-standard-8` | 24 GB | ~$0.50 | Development, small/medium models |
| T4 | `n1-standard-8` | 16 GB | ~$0.35 | Budget inference |
| A100 40GB | `a2-highgpu-1g` | 40 GB | ~$3.60 | Large models, production |
| A100 80GB | `a2-ultragpu-1g` | 80 GB | ~$5.10 | Maximum VRAM |

### Network

| Variable | Default | Description |
|----------|---------|-------------|
| `create_network` | `true` | Create VPC and subnet (set `false` to use existing) |
| `network` | `sie-network` | VPC name |
| `subnetwork` | `sie-subnet` | Subnetwork name |
| `subnet_cidr` | `10.0.0.0/20` | CIDR range for the subnetwork |
| `pods_cidr` | `10.1.0.0/16` | Secondary CIDR range for pods |
| `services_cidr` | `10.2.0.0/20` | Secondary CIDR range for services |
| `enable_private_nodes` | `true` | No public IPs on nodes (Cloud NAT for egress) |
| `master_ipv4_cidr_block` | `172.16.0.0/28` | CIDR block for the master network |
| `authorized_networks` | `[]` | CIDRs allowed to access the Kubernetes API |

### Node Auto-Provisioning (NAP)

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_node_auto_provisioning` | `true` | Let GKE auto-create node pools for pending pods |
| `nap_max_cpu` | `1000` | Maximum CPU cores NAP can provision |
| `nap_max_memory_gb` | `4000` | Maximum memory NAP can provision |

### SIE application

| Variable | Default | Description |
|----------|---------|-------------|
| `install_sie` | `true` | Install SIE via the Helm chart |
| `sie_bundle` | `default` | Server bundle (deprecated: use `sie_bundles`) |
| `sie_bundles` | `[]` | List of bundles to deploy (creates worker pools per gpu x bundle) |
| `sie_router_replicas` | `2` | Router replicas for HA |
| `sie_router_service_type` | `ClusterIP` | `ClusterIP` or `LoadBalancer` |
| `sie_autoscaling_cooldown` | `600` | Seconds before KEDA scales to zero |
| `sie_hf_token` | `""` | HuggingFace token for gated models (sensitive) |
| `sie_server_image` | `ghcr.io/superlinked/sie-server` | Server Docker image |
| `sie_router_image` | `ghcr.io/superlinked/sie-router` | Router Docker image |
| `sie_image_tag` | `""` | Server image tag (defaults to Chart appVersion) |
| `sie_cache_volume_size` | `50Gi` | Persistent volume size for model cache |

### NATS config distribution

NATS enables runtime model management — add, remove, and update models via the router API without redeploying. The config store persists API-added models so they survive router restarts.

| Variable | Default | Description |
|----------|---------|-------------|
| `nats_enabled` | `false` | Enable NATS-based config distribution |
| `nats_install` | `true` | Deploy NATS server as a sub-chart (set `false` for external NATS) |
| `nats_url` | `""` | External NATS server URL (required when `nats_install=false`) |
| `nats_config_store_bucket` | `""` | GCS bucket name for config persistence (creates bucket + IAM automatically) |
| `nats_config_store_dir` | `/tmp/sie-config-store` | Config store path (overridden when `nats_config_store_bucket` is set) |
| `nats_config_restore` | `false` | Restore API-added models from config store on router startup |

**Enable persistent config distribution:**

```hcl
module "sie_gke" {
  source = "superlinked/sie/google"

  nats_enabled              = true
  nats_config_store_bucket  = "my-project-sie-configs"  # Creates GCS bucket + IAM
  nats_config_restore       = true                      # Restore on restart
}
```

**Use external NATS:**

```hcl
module "sie_gke" {
  source = "superlinked/sie/google"

  nats_enabled = true
  nats_install = false
  nats_url     = "nats://my-nats-cluster:4222"
}
```

### Ingress + auth

| Variable | Default | Description |
|----------|---------|-------------|
| `install_ingress_nginx` | `false` | Install ingress-nginx controller |
| `sie_ingress_enabled` | `false` | Expose router via ingress |
| `sie_ingress_host` | `""` | Hostname (empty = catch-all) |
| `sie_ingress_tls_enabled` | `false` | Enable TLS |
| `sie_auth_enabled` | `false` | Enable oauth2-proxy for OIDC auth |
| `sie_auth_oidc_issuer_url` | `""` | OIDC issuer URL (required when auth enabled) |
| `sie_router_auth_mode` | `none` | `none` or `static` (shared secret) |

**Minimal auth setup (static token):**

```bash
# Create a shared secret
kubectl create secret generic sie-auth -n sie --from-literal=SIE_AUTH_TOKEN="your-token"

# Set variables
export TF_VAR_sie_router_auth_mode="static"
export TF_VAR_sie_router_auth_secret_name="sie-auth"
```

**OIDC auth with Dex:**

```bash
export TF_VAR_install_dex=true
export TF_VAR_dex_values_yaml="$(cat dex-values.yaml)"
export TF_VAR_sie_auth_enabled=true
export TF_VAR_sie_auth_oidc_issuer_url="http://dex.dex.svc.cluster.local:5556/dex"
```

### Observability

| Variable | Default | Description |
|----------|---------|-------------|
| `external_prometheus_url` | `""` | Skip built-in Prometheus, use your own |
| `install_loki` | `true` | Log aggregation with Loki + Alloy |
| `install_tempo` | `false` | Distributed tracing with Tempo |
| `enable_cloud_logging` | `true` | GKE native Cloud Logging |
| `enable_managed_prometheus` | `false` | GKE Managed Prometheus (for GCP Console) |
| `prometheus_retention` | `15d` | Prometheus data retention period |
| `prometheus_storage_size` | `100Gi` | Prometheus persistent volume size |
| `grafana_admin_password` | `admin` | Grafana admin password (change in production!) |

## Outputs

After `terraform apply`, use these outputs to connect and deploy:

| Output | Description |
|--------|-------------|
| `kubectl_config_command` | Run this to configure kubectl |
| `cluster_name` | GKE cluster name |
| `cluster_endpoint` | GKE cluster API endpoint (sensitive) |
| `artifact_registry_url` | Where to push Docker images |
| `sie_workload_service_account` | Pass to Helm for Workload Identity |
| `workload_identity_annotation` | Direct annotation for K8s service account |
| `gpu_node_pools` | GPU pool configs (for Helm worker pool mapping) |
| `config_store_bucket` | GCS bucket URL for NATS config store (if created) |

## Architecture

```
                      +----------------------------------------------------------+
                      |                    GCP Project                           |
                      |                                                          |
+----------+          |  +----------------------------------------------------+  |
|          |  HTTPS   |  |              VPC (private nodes + Cloud NAT)       |  |
|  Client  |--------> |  |                                                    |  |
|          |          |  |  +----------------------------------------------+  |  |
+----------+          |  |  |     GKE Cluster                              |  |  |
                      |  |  |                                              |  |  |
                      |  |  |  +------------+    +----------------------+  |  |  |
                      |  |  |  |   Router   |--->|    GPU Workers       |  |  |  |
                      |  |  |  |   (NATS)   |    |  (L4 / A100 / T4)    |  |  |  |
                      |  |  |  +------------+    +----------------------+  |  |  |
                      |  |  |        |                      |              |  |  |
                      |  |  |  +--------------------------------------------+  |  |
                      |  |  |  |  KEDA . Prometheus . Grafana . Loki . NATS  |  |  |
                      |  |  |  +--------------------------------------------+  |  |
                      |  |  |                                              |  |  |
                      |  |  |  +--------------+  +----------------------+  |  |  |
                      |  |  |  |  CPU Pool    |  |  GPU Pool(s)         |  |  |  |
                      |  |  |  | (e2-std-4)   |  |  (g2/a2/n1 + spot)   |  |  |  |
                      |  |  |  +--------------+  +----------------------+  |  |  |
                      |  |  +----------------------------------------------+  |  |
                      |  |                                                    |  |
                      |  |  +----------------+  +------------+  +---------+   |  |
                      |  |  |  Artifact Reg. |  |  Cloud NAT |  |   IAM   |   |  |
                      |  |  |  (images)      |  |  (egress)  |  |  (WI)   |   |  |
                      |  |  +----------------+  +------------+  +---------+   |  |
                      |  |                                                    |  |
                      |  |  +--------------------------------------------+    |  |
                      |  |  |  GCS Config Store (NATS persistence)       |    |  |
                      |  |  +--------------------------------------------+    |  |
                      |  +----------------------------------------------------+  |
                      +----------------------------------------------------------+
```

## Pushing images to Artifact Registry
>
> This is optional, because the official image is available at `ghcr.io/superlinked/`.

After `terraform apply`, push your SIE Docker images:

```bash
# Authenticate Docker to Artifact Registry
gcloud auth configure-docker $(terraform output -raw artifact_registry_url | cut -d/ -f1)

# Push server image
docker tag sie-server:latest $(terraform output -raw artifact_registry_url)/sie-server:latest
docker push $(terraform output -raw artifact_registry_url)/sie-server:latest

# Push router image
docker tag sie-router:latest $(terraform output -raw artifact_registry_url)/sie-router:latest
docker push $(terraform output -raw artifact_registry_url)/sie-router:latest
```

## Security features

This module follows GCP security best practices out of the box:

- **Private nodes** — worker nodes have no public IPs; egress via Cloud NAT
- **Shielded nodes** — Secure Boot and Integrity Monitoring on all node pools
- **Workload Identity** — pods use GCP service accounts, no JSON key files
- **Least-privilege IAM** — node SA has only logging, monitoring, and Artifact Registry reader
- **VPC-native networking** — pod and service CIDRs use secondary IP ranges (alias IPs)
- **GPU taints** — GPU nodes are tainted so only GPU workloads schedule on them
- **Image streaming** — GCFS enabled for fast container startup
- **Registry cleanup** — automatic deletion of dev/test images after 14 days, untagged after 30 days
- **Legacy endpoints disabled** — metadata concealment on all nodes
- **Config store bucket** — uniform bucket-level access, public access prevention enforced

## Cleanup

```bash
terraform destroy
```

**Important**: GPU nodes can be expensive. Always destroy dev/test clusters when not in use. Spot VMs (`spot = true`) save 60-91% but may be preempted.

If `deletion_protection = true` (default for production), you must first disable it:

```bash
terraform apply -var="deletion_protection=false"
terraform destroy
```
