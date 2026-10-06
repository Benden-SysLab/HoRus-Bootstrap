# HoRus-Bootstrap

Terraform bootstrap for the rebuilt four-node HoRus Proxmox VE cluster. The
repository manages 28 workloads—21 unprivileged LXC containers and 7 virtual
machines—together with their placement, compute, network and private storage
attachments.

Russian documentation: [README.RU.md](README.RU.md). Detailed design:
[ARCHITECTURE.md](ARCHITECTURE.md).

## Status

The current topology has been deployed and converged. After the completed
bootstrap, `terraform plan -parallelism=5` returned:

```text
No changes. Your infrastructure matches the configuration.
```

This confirms convergence between Terraform state, provider-managed resources,
the LXC placement helper and the actual Proxmox configuration. The provider is
pinned to `bpg/proxmox 0.115.0`.

## Architecture overview

[`topology.tf`](topology.tf) is the only workload inventory. The root module
derives two dynamic module sets from it:

```text
local.workloads
  +-- module.virtual_machines (for_each)
  `-- module.lxc_containers   (for_each)
```

Terraform owns infrastructure placement and identity. A later Ansible/service
layer owns packages, services, application users, data ownership inside guests
and guest-level shared-data mounts.

## Physical cluster

| Node | CPU | RAM | Primary role |
|---|---|---:|---|
| `horus-pmx-node01` | Xeon E3-1275v2 | ~31 GiB | Guardian/security, CI, load balancing, CasaOS/media, Kubernetes worker |
| `horus-pmx-node02` | Xeon E3-1275v2, RTX 3060 12 GB | ~31 GiB | Mimir AI, Ansible, Authentik, Joyfilm, Kubernetes |
| `horus-pmx-node03` | i7-3770K | ~15.6 GiB | Storage, Golden factory, core infrastructure |
| `horus-pmx-node04` | i5-4210U | ~15.5 GiB | Observability, System Guardian |

Management addresses, CIDR, gateway and physical storage paths are required
environment-specific values supplied through the ignored `terraform.tfvars`.

## Network

All workloads use bridge `vmbr0`. Gateways are derived from the central VLAN
map; there is no global workload gateway.

| VLAN | Name |
|---:|---|
| 101 | INFRA |
| 110 | TRUSTED |
| 120 | IOT |
| 130 | QUARANTINE |
| 140 | STORAGE |
| 150 | OBS/SEC |
| 160 | AI |
| 170 | DMZ |
| 180 | K8S-LAB |

Real workload addresses, VLAN CIDRs and gateways are supplied through the
ignored `terraform.tfvars`; Terraform validates every workload/VLAN mapping.

Kubernetes Pod and Service CIDRs are environment-specific values kept in the
private network design rather than documented in this public repository.

## Workload inventory

| Node | VMID | Type | Hostname | VLAN |
|---|---:|---|---|---:|
| Node01 | 101 | LXC | `horus-lb-srv01` | 170 |
| Node01 | 102 | LXC | `horus-agent-srv01` | 101 |
| Node01 | 103 | VM | `horus-jnk-srv01` | 101 |
| Node01 | 104 | LXC | `horus-ai-srv01` | 150 |
| Node01 | 105 | LXC | `horus-db-srv01` | 150 |
| Node01 | 106 | VM | `horus-media-srv01` | 101 |
| Node01 | 107 | VM | `horus-k8sw-srv01` | 180 |
| Node02 | 201 | LXC | `horus-ans-srv01` | 101 |
| Node02 | 202 | LXC | `horus-ai-srv02` | 160 |
| Node02 | 203 | LXC | `horus-db-srv02` | 160 |
| Node02 | 204 | LXC | `horus-vec-srv01` | 160 |
| Node02 | 205 | LXC | `horus-cache-srv01` | 160 |
| Node02 | 206 | LXC | `horus-iam-srv01` | 101 |
| Node02 | 207 | LXC | `horus-media-srv02` | 101 |
| Node02 | 208 | VM | `horus-k8sw-srv02` | 180 |
| Node02 | 209 | VM | `horus-k8sc-srv01` | 180 |
| Node03 | 301 | LXC | `horus-db-srv03` | 101 |
| Node03 | 302 | VM | `horus-vlt-srv01` | 101 |
| Node03 | 303 | LXC | `horus-wiki-srv01` | 101 |
| Node03 | 304 | LXC | `horus-git-srv01` | 101 |
| Node03 | 305 | VM | `horus-work-srv01` | 101 |
| Node03 | 306 | LXC | `horus-reg-srv01` | 101 |
| Node04 | 401 | LXC | `horus-grf-srv01` | 150 |
| Node04 | 402 | LXC | `horus-pm-srv01` | 150 |
| Node04 | 403 | LXC | `horus-lok-srv01` | 150 |
| Node04 | 404 | LXC | `horus-otel-srv01` | 150 |
| Node04 | 405 | LXC | `horus-s3-srv01` | 150 |
| Node04 | 406 | LXC | `horus-ai-srv03` | 150 |

Node totals are 7 / 9 / 6 / 6. VMID 307 is reserved and is not created by
Terraform.

## Golden templates

The templates are external prerequisites and are not in Terraform state.
Terraform must never create, import, replace or destroy them.

| VMID | Type | Location | Root baseline | Properties |
|---:|---|---|---:|---|
| 9000 | Debian 13 VM | Node03 / `local-lvm` | 12 GiB | VM clone source |
| 9001 | Debian 13 LXC | Node03 / `storage-infra` | 8 GiB | unprivileged, shared clone source |

### VM lifecycle

VM provisioning is provider-native:

```text
Golden 9000 on Node03/local-lvm
  -> full clone with migrate=true
  -> final target node/local-lvm
  -> requested disk size and Cloud-Init network/DNS
  -> started=true and on_boot=true
```

No external placement script is used for VMs.

### LXC lifecycle

Proxmox requires shared target storage for a cross-node LXC clone. A direct
clone from Node03 to another node's non-shared `local-lvm` fails with
`can't clone to non-shared storage 'local-lvm'`. The supported lifecycle is:

```text
Golden 9001 on Node03/storage-infra
  -> provider full clone
  -> final target node/storage-infra, stopped
  -> same-node placement helper
  -> pct move-volume rootfs to local-lvm
  -> grow rootfs only when requested size is larger
  -> verify identity, node, storage, size, mounts and network
  -> pct start
  -> running with onboot=1
```

The helper does not migrate containers between nodes. It is idempotent,
never shrinks disks and fails closed on an unexpected identity, node, storage,
lock, network or mount configuration.

Provider ownership includes existence, VMID, hostname, CPU, RAM, final node,
clone identity, network, VLAN, IP, gateway, features, unprivileged state,
private mount declarations and `start_on_boot`. The helper owns only the
unavoidable post-clone rootfs move, safe grow, final verification and start.

Three narrow `ignore_changes` entries encode that boundary:

- `started`: the helper starts the CT only after placement verification;
- `disk[0].datastore_id`: the helper performs the unsupported in-place move to
  final `local-lvm`;
- `disk[0].size`: the helper performs upward-only growth after the move.

They are not generic drift suppression. The helper validates the desired final
state whenever its stable desired specification or implementation revision
changes.

## Storage model

Private application state is single-owner data attached as Proxmox-managed LXC
mount-point volumes. It is not shared application data.

| Service/data | Owner | Logical datastore |
|---|---|---|
| Guardian PostgreSQL | Node01 / `horus-db-srv01` | `guardian-data` |
| Mimir, AI PostgreSQL, Qdrant | Node02 / respective workloads | `mimir-data` |
| Infrastructure PostgreSQL, Wiki, Gitea | Node03 / respective workloads | `storage-infra` |
| OCI Registry | Node03 / `horus-reg-srv01` | `artifacts-data` |
| MinIO | Node04 / `horus-s3-srv01` | `logs-data` |

Physical host paths, guest mount paths and NFS endpoints are supplied through
the ignored `terraform.tfvars`.

Terraform declares `guardian-data`, `mimir-data`, `artifacts-data` and
`logs-data` only over already-mounted physical roots, with
`create_base_path = false`. Existing `storage-infra` supplies Golden 9001 and
Node03 private volumes. Guardian AI does not receive raw PostgreSQL files.

Shared media and build artifacts are separate metadata for later guest-level
NFS configuration. Bootstrap does not configure application services, mount NFS
inside guests, invent UID/GID mappings or change ownership of shared trees.

## Security model

The Golden baseline disables root SSH inside guests. `abbenden-srv` uses an SSH
key and password-protected sudo; no blanket `NOPASSWD` is granted.
`jenkins-srv` uses an SSH key and has no broad sudo access. All LXC containers
are unprivileged.

The operator provides only a local key file path for the Proxmox-node placement
connection. Never commit credentials, private-key content or passwords.

## Prerequisites and configuration

- reachable four-node Proxmox VE cluster and API endpoint;
- external Golden templates 9000 and 9001 in the locations above;
- verified physical storage mounts and existing `storage-infra`;
- Terraform, PowerShell 7 and OpenSSH client on the operator host;
- API credentials with required guest/storage permissions;
- key-based root SSH to Proxmox nodes with verified host keys.

Copy `terraform.tfvars.example` to an ignored local `terraform.tfvars`, then set
the endpoint, credentials and operator key path. Do not commit secrets.

## First bootstrap or mass LXC recreation

```powershell
terraform init
terraform validate
terraform plan -parallelism=1
terraform apply -parallelism=1
```

Proxmox places `lock: disk` on source CT 9001 during a clone. Concurrent clones
from the single Golden 9001 can fail with `CT is locked (disk)`. Provider
0.115.0 has no per-template mutex, so global parallelism 1 is required for a
fresh or replacement-heavy LXC rollout.

## Normal steady-state operation

```powershell
terraform plan -parallelism=5
terraform apply -parallelism=5
```

Parallelism 5 is appropriate after bootstrap for independent VM, storage and
configuration changes. Review every plan: if it contains multiple LXC
create/replace operations sourced from 9001, return to parallelism 1.

## Validation and tests

```powershell
terraform fmt -recursive
terraform fmt -check -recursive
terraform validate
terraform test
pwsh -NoProfile -File tests/lxc_placement.tests.ps1
```

Current results: 5 Terraform tests passed, 0 failed; 7 offline placement tests
passed.

## Known limitations

- One Golden LXC source serializes mass LXC cloning.
- Safe parallel clone lanes would require additional approved immutable Golden
  replicas; this is future work, not current infrastructure.
- The approved thin-provisioning model overcommits `local-lvm` on Node02,
  Node03 and Node04; see [RESOURCE_PLAN.md](RESOURCE_PLAN.md).
- Application provisioning and guest-level shared mounts belong to the later
  Ansible/service layer.

## Repository structure

| Path | Purpose |
|---|---|
| `topology.tf` | authoritative nodes, VLANs, workloads and storage consumers |
| `main.tf` | storage resources and dynamic VM/LXC module calls |
| `modules/proxmox_vm/` | provider-native VM lifecycle |
| `modules/proxmox_lxc/` | provider-owned LXC and placement barrier |
| `scripts/lxc_placement.ps1` | minimal Terraform entry point for LXC placement |
| `scripts/lib/Horus.LxcPlacement.ps1` | fail-closed placement implementation |
| `tests/` | inventory, module and offline helper tests |
| `ARCHITECTURE.md` | ownership and design rationale |
| `BACKLOG.md` | remaining work |

## Operational safety

Always inspect `terraform plan` before apply. Golden 9000/9001 and physical
storage mounts are external prerequisites. Never use state commands to hide a
real VMID/type replacement, and never force-unlock a guest automatically.

This project is licensed under the [Apache License 2.0](LICENSE). Repository:
[Benden-SysLab/HoRus-Bootstrap](https://github.com/Benden-SysLab/HoRus-Bootstrap).
