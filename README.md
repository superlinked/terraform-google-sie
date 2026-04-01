# SIE GKE Terraform Module

One command to get a GPU-ready GKE cluster for [SIE](https://github.com/superlinked/sie) (Search Inference Engine). The module creates everything you need — VPC, GKE, GPU node pools, container registry, observability — so you can focus on running inference, not managing infrastructure.

## What you get

- **GKE cluster** with VPC-native networking, private nodes, and Cloud NAT
- **GPU node pools** — L4, T4, A100, or A100-80GB, with automatic driver installation
- **Scale-to-zero** — GPU nodes scale down to zero when idle, so you only pay when running inference
- **Node Auto-Provisioning (NAP)** — GKE automatically creates node pools to fit pending workloads
- **Artifact Registry** — private Docker registry with automatic cleanup policies for dev images
- **Workload Identity** — pods authenticate to GCP without service account keys
- **Observability-ready** — outputs for Prometheus, Grafana, and KEDA integration via the SIE Helm chart
- **Optional SIE application** — deploy the full SIE stack (router, workers, KEDA, Prometheus) via Helm
- **Optional git-sync** — hot-reload model/bundle configs from a Git repository without redeploying
- **Optional ingress + auth** — ingress-nginx with oauth2-proxy or static token auth

## Quick start

```bash
cd examples/dev-l4-spot
export TF_VAR_project_id="your-project-id"
terraform init
terraform plan
terraform apply
```

That's it. After apply, configure kubectl and deploy SIE via Helm:

```bash
# Point kubectl at the new cluster
$(terraform output -raw kubectl_config_command)

# Deploy SIE (router, workers, KEDA, Prometheus, Grafana)
helm upgrade --install sie-cluster oci://ghcr.io/superlinked/charts/sie-cluster --version 0.1.8 \
  -f values-gke.yaml \
  --create-namespace -n sie \
  --set serviceAccount.annotations."iam\.gke\.io/gcp-service-account"="$(terraform output -raw sie_workload_service_account)"
```

## Examples

| Example | GPU | Cost | Description |
|---------|-----|------|-------------|
| [`dev-l4-spot`](examples/dev-l4-spot/) | L4 (g2-standard-8) | ~$0.50/hr | Spot instances, scale 0-5 nodes, minimal cost for development |

## Prerequisites

1. **GCP project** with billing enabled
2. **GPU quota** in your target region — check with: `gcloud compute regions describe REGION --format="table(quotas.filter(metric:NVIDIA))"`. Request increases at [IAM & Admin > Quotas](https://console.cloud.google.com/iam-admin/quotas).
3. **APIs enabled**: `container.googleapis.com`, `compute.googleapis.com`, `artifactregistry.googleapis.com`
4. **Terraform** >= 1.14

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

### GPU configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `gpu_node_pools` | 1x L4 spot pool | List of GPU node pool configurations (see below) |
| `cpu_node_pool` | e2-standard-4 | CPU pool for system workloads (kube-system, monitoring) |

Each entry in `gpu_node_pools` supports:

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `name` | yes | — | Pool name (e.g., `l4-spot`) |
| `machine_type` | yes | — | GCE machine type |
| `gpu_type` | yes | — | Accelerator type |
| `gpu_count` | yes | — | GPUs per node |
| `min_node_count` | yes | — | Minimum nodes (0 = scale-to-zero) |
| `max_node_count` | yes | — | Maximum nodes |
| `spot` | no | `false` | Use spot VMs (~60-91% savings) |
| `disk_size_gb` | no | `100` | Boot disk size |
| `local_ssd_count` | no | `0` | NVMe local SSDs for model cache |
| `zones` | no | all | Restrict to specific zones |

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
| `enable_private_nodes` | `true` | No public IPs on nodes (Cloud NAT for egress) |
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
| `sie_bundle` | `default` | Server bundle (`default` or `sglang`) |
| `sie_bundles` | `[]` | Multiple bundles (creates worker pools per gpu x bundle) |
| `sie_router_replicas` | `2` | Router replicas for HA |
| `sie_autoscaling_cooldown` | `600` | Seconds before KEDA scales to zero |
| `sie_hf_token` | `""` | HuggingFace token for gated models (sensitive) |
| `sie_router_service_type` | `ClusterIP` | `ClusterIP` or `LoadBalancer` |

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

### Config hot reload (git-sync)

| Variable | Default | Description |
|----------|---------|-------------|
| `sie_git_sync_enabled` | `false` | Auto-reload model/bundle configs from Git |
| `sie_git_sync_repo` | `""` | Git repository URL |
| `sie_git_sync_branch` | `main` | Branch to sync |
| `sie_git_sync_period` | `60s` | Sync interval |
| `sie_git_sync_ssh_secret` | `""` | K8s secret for SSH key (private repos) |

```hcl
# Public repo
module "sie_gke" {
  source = "superlinked/sie/google"

  sie_git_sync_enabled = true
  sie_git_sync_repo    = "https://github.com/your-org/sie-configs"
}

# Private repo (create SSH key + K8s secret first)
module "sie_gke" {
  source = "superlinked/sie/google"

  sie_git_sync_enabled    = true
  sie_git_sync_repo       = "git@github.com:your-org/sie-configs.git"
  sie_git_sync_ssh_secret = "git-ssh"
}
```

### Observability

| Variable | Default | Description |
|----------|---------|-------------|
| `external_prometheus_url` | `""` | Skip built-in Prometheus, use your own |
| `install_loki` | `true` | Log aggregation with Loki + Alloy |
| `install_tempo` | `false` | Distributed tracing with Tempo |
| `enable_cloud_logging` | `true` | GKE native Cloud Logging |
| `enable_managed_prometheus` | `false` | GKE Managed Prometheus (for GCP Console) |

## Outputs

After `terraform apply`, use these outputs to connect and deploy:

| Output | Description |
|--------|-------------|
| `kubectl_config_command` | Run this to configure kubectl |
| `cluster_name` | GKE cluster name |
| `artifact_registry_url` | Where to push Docker images |
| `sie_workload_service_account` | Pass to Helm for Workload Identity |
| `workload_identity_annotation` | Direct annotation for K8s service account |
| `gpu_node_pools` | GPU pool configs (for Helm worker pool mapping) |
| `prometheus_url` | Prometheus URL for queries |
| `grafana_url` | Grafana URL (port-forward to access) |
| `router_url` | Router base URL (ingress or LB) |

## Architecture

```
                      ┌──────────────────────────────────────────────────────────┐
                      │                    GCP Project                           │
                      │                                                          │
┌──────────┐          │  ┌────────────────────────────────────────────────────┐  │
│          │  HTTPS   │  │              VPC (private nodes + Cloud NAT)       │  │
│  Client  │────────▶ │  │                                                    │  │
│          │          │  │  ┌──────────────────────────────────────────────┐  │  │
└──────────┘          │  │  │     GKE Cluster                              │  │  │
                      │  │  │                                              │  │  │
                      │  │  │  ┌────────────┐    ┌──────────────────────┐  │  │  │
                      │  │  │  │   Router   │───▶│    GPU Workers       │  │  │  │
                      │  │  │  │ (git-sync) │    │  (L4 / A100 / T4)    │  │  │  │
                      │  │  │  └────────────┘    └──────────────────────┘  │  │  │
                      │  │  │        │                      │              │  │  │
                      │  │  │  ┌─────┴──────────────────────┴──────────┐   │  │  │
                      │  │  │  │  KEDA · Prometheus · Grafana · Loki   │   │  │  │
                      │  │  │  └───────────────────────────────────────┘   │  │  │
                      │  │  │                                              │  │  │
                      │  │  │  ┌──────────────┐  ┌──────────────────────┐  │  │  │
                      │  │  │  │  CPU Pool    │  │  GPU Pool(s)         │  │  │  │
                      │  │  │  │ (e2-std-4)   │  │  (g2/a2/n1 + spot)   │  │  │  │
                      │  │  │  └──────────────┘  └──────────────────────┘  │  │  │
                      │  │  └──────────────────────────────────────────────┘  │  │
                      │  │                                                    │  │
                      │  │  ┌────────────────┐  ┌────────────┐  ┌─────────┐   │  │
                      │  │  │  Artifact Reg. │  │  Cloud NAT │  │   IAM   │   │  │
                      │  │  │  (images)      │  │  (egress)  │  │  (IRSA) │   │  │
                      │  │  └────────────────┘  └────────────┘  └─────────┘   │  │
                      │  └────────────────────────────────────────────────────┘  │
                      └──────────────────────────────────────────────────────────┘
```

## Pushing images to Artifact Registry
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
