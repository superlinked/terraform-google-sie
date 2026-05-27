# SIE GKE Terraform Module

One command to get a GPU-ready GKE cluster for [SIE](https://github.com/superlinked/sie) (Search Inference Engine). The module creates the underlying GCP resources (VPC, GKE, GPU node pools, Artifact Registry, IAM, optional model-cache GCS bucket); the SIE application itself — gateway, sie-config, workers, KEDA, Prometheus, Grafana, Loki, NATS — is deployed on top via the [sie-cluster Helm chart](../../helm/sie-cluster/).

- GPU node pools sized for scale-to-zero via KEDA (configured in the Helm chart)
- Artifact Registry with cleanup policies
- Workload Identity for GCS access

## What you get

- **GKE cluster** with VPC-native networking, private nodes, and Cloud NAT
- **GPU node pools** — L4, T4, A100, or A100-80GB, with automatic driver installation
- **Scale-to-zero** — GPU nodes scale down to zero when idle, so you only pay when running inference
- **Node Auto-Provisioning (NAP)** — GKE automatically creates node pools to fit pending workloads
- **Artifact Registry** — private Docker registry with automatic cleanup policies for dev images
- **Workload Identity** — pods authenticate to GCP without service account keys
- **Observability-ready** — outputs wired for the Helm chart's Prometheus, Grafana, Loki, and KEDA integration
- **Paired with the sie-cluster Helm chart** — Kubernetes workloads (gateway, sie-config, workers, NATS, ingress, auth) are installed on top of this cluster via Helm

## Module structure

| Layer | Path | What it creates |
|-------|------|-----------------|
| **Infrastructure** | `infra/` | GCP resources only: VPC, GKE cluster, node pools, IAM, Artifact Registry, optional model-cache GCS bucket. Can be applied without a running cluster. |
| **Application** | [sie-cluster Helm chart](../../helm/sie-cluster/) | Kubernetes resources: sie-config, gateway, workers, NATS, KEDA, Prometheus, Grafana, Loki, optional ingress + oauth2-proxy. Applied after the cluster is up. |

Examples in `examples/` use the `infra/` submodule directly and deploy K8s resources via the Helm chart in a follow-up step.

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

# Deploy SIE (gateway, workers, KEDA, Prometheus, Grafana)
helm upgrade --install sie-cluster ../../deploy/helm/sie-cluster \
  -f ../../deploy/helm/sie-cluster/values-gke.yaml \
  --create-namespace -n sie \
  --set serviceAccount.annotations."iam\.gke\.io/gcp-service-account"="$(terraform output -raw workload_identity_annotation)"
```

## Examples

| Example | GPU | Description |
|---------|-----|-------------|
| [`dev-l4-spot`](examples/dev-l4-spot/) | L4 (g2-standard-8) | Spot instances, scale 0-5 nodes, minimal cost for development |

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
| `kubelet_container_log_max_size` | `20Mi` | Per-container kubelet log file size before rotation |
| `kubelet_container_log_max_files` | `30` | Rotated files retained per container; kubelet retention is size/count based, not hourly |

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

### Application layer

The `infra/` module only creates GCP resources (VPC, GKE, node pools, IAM, Artifact Registry). The SIE application — gateway, sie-config, workers, observability stack, NATS, optional ingress + auth — is deployed separately via the [sie-cluster Helm chart](../../helm/sie-cluster/). All `install_*`, `sie_*`, and `nats_*` knobs live on the Helm values file (see `deploy/helm/sie-cluster/values.yaml`), not on this Terraform module.

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
                      |  |  |  |   Gateway  |--->|    GPU Workers       |  |  |  |
                      |  |  |  |  (consumer)|    |  (L4 / A100 / T4)    |  |  |  |
                      |  |  |  +------+-----+    +----------------------+  |  |  |
                      |  |  |         |                    |               |  |  |
                      |  |  |  +------+-----+              |               |  |  |
                      |  |  |  | sie-config |  (writes + NATS deltas)      |  |  |
                      |  |  |  +------------+              |               |  |  |
                      |  |  |                              |               |  |  |
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

# Push gateway image
docker tag sie-gateway:latest $(terraform output -raw artifact_registry_url)/sie-gateway:latest
docker push $(terraform output -raw artifact_registry_url)/sie-gateway:latest

# Push sie-config image
docker tag sie-config:latest $(terraform output -raw artifact_registry_url)/sie-config:latest
docker push $(terraform output -raw artifact_registry_url)/sie-config:latest
```

## Model cache and payload store

SIE clusters benefit from two object-store backed features that share a single GCS bucket:

- **Model cache**: pre-staged model weights at `gs://<bucket>/models/`, so workers cold-start from object storage rather than re-downloading from Hugging Face on every pod spin-up.
- **Payload store**: large work-item payloads (images, long documents that exceed the 1 MiB NATS in-band budget) at `gs://<bucket>/payloads/`, written by the gateway and read once by the worker. Garbage-collected by a runtime TTL plus a bucket lifecycle rule.

Set `create_model_cache = true` and the module:

1. Provisions a managed GCS bucket with uniform bucket-level access, public-access prevention enforced, and a lifecycle rule that deletes objects under the `payloads/` prefix after one day (configurable via `model_cache_payload_expiration_days`).
2. Defines two custom IAM roles (`sie_model_cache_reader`, `sie_payload_store_writer`) with the minimum permission set each side needs.
3. Binds both roles to the SIE workload service account with **IAM Conditions** that scope each role to its own top-level prefix (`models/` for read, `payloads/` for read/write/delete). Workers can read weights but cannot delete or overwrite them; the gateway can write and delete payload refs but cannot touch weights.

After apply, pass the bucket into Helm with one terraform output:

```bash
helm upgrade --install sie-cluster ../../deploy/helm/sie-cluster \
  -f ../../deploy/helm/sie-cluster/values-gke.yaml \
  --create-namespace -n sie \
  --set serviceAccount.annotations."iam\.gke\.io/gcp-service-account"="$(terraform output -raw workload_identity_annotation)" \
  $(terraform output -raw model_cache_helm_args)
```

The chart auto-derives `payloadStore.url` from `workers.common.clusterCache.url`, so a single `--set` for the cache covers both features. Operators who manage their own bucket can opt out (`create_model_cache = false`, default) and pass `gcs_bucket_name` instead; that path keeps the broader `roles/storage.objectViewer` binding for backward compatibility, but you forgo the prefix-scoped roles and the lifecycle rule.

See `infra/gcs_model_cache.tf` and `infra/iam.tf` for the resource definitions and condition expressions.

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

## Bring-your-own components

Some pieces of a production deployment are intentionally not turnkey — either because they're cluster-wide / cross-stack concerns (registry, OIDC) or because they require domains and DNS records that only you can own (TLS, DNS). This module lets you opt out where it makes sense and points at the right knobs.

- **Container registry** — optional. The module manages a regional Artifact Registry by default (`create_artifact_registry = true`, see [`infra/variables.tf:263`](infra/variables.tf)). Set `create_artifact_registry = false` to reuse a registry managed by another stack in the same project; the `artifact_registry_url` output is still emitted so Helm / Workload Identity wiring is unchanged. To use any external registry, point the Helm chart at it via `gateway.image.repository`, `workers.common.image.repository`, and `config.image.repository`.
- **TLS certificate** — BYO by default. Set `ingress.tls.mode` to one of:
  - `byo` — supply your own `kubernetes.io/tls` Secret.
  - `cert-manager` — install cert-manager once in the cluster; the chart annotates the Ingress for automated Let's Encrypt issuance via HTTP-01.
  - `self-signed` — for air-gapped clusters; set `certManagerBundle.certManager.install: true` to bundle cert-manager (single-tenant clusters only).

  See the [chart README's TLS / HTTPS section](../../helm/sie-cluster/README.md#tls--https). DNS-01 / wildcard / Google-managed certificate paths are out of scope for the chart.
- **DNS / domain** — always BYO. This module does not provision Cloud DNS zones or records. After `terraform apply`, take the ingress controller's LoadBalancer IP (`kubectl -n ingress-nginx get svc ingress-nginx-controller`) and create an A/AAAA record pointing at it under a domain you control.
- **OIDC provider** — BYO. When `auth.enabled: true` in the chart, set `auth.oauth2Proxy.oidcIssuerUrl` and the corresponding client ID / secret to your existing identity provider (Okta, Auth0, Google Workspace, Azure AD, …). The module does not create an IdP.

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
