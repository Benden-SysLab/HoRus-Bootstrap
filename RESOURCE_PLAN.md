# HoRus resource-aware placement

Physical capacity is taken from the live Proxmox cluster observed on 2026-08-17:

| Node | CPU | RAM | Planned guest CPU | Planned guest RAM |
|---|---:|---:|---:|---:|
| horus-pmx-node01 | 8 | 32 GB | 20 | 22 GB |
| horus-pmx-node02 | 8 | 32 GB | 19 | 27 GB |
| horus-pmx-node03 | 8 | 16 GB | 10 | 13 GB |
| horus-pmx-node04 | 4 | 16 GB | 12 | 14 GB |

CPU is intentionally oversubscribed because most HoRus services are low-utilization Linux workloads. RAM is the hard placement constraint and is validated by Terraform.

## Placement

### node01 — compute / GPU / media

- horus-jnk-srv01 — 2 vCPU / 4 GB
- horus-ai-srv01 — 4 / 4
- horus-ai-srv02 — 4 / 4
- horus-media-srv01 — 2 / 2
- horus-media-srv02 — 4 / 4
- horus-agent-srv01 — 4 / 4

GPU/media affinity keeps the GPU and NVENC workloads on the current compute/media node. Agent is colocated with Jenkins and build-heavy workloads.

### node02 — AI / build / infrastructure

- horus-ai-srv03 — 4 / 8
- horus-build-srv01 — 4 / 4
- horus-lab-srv01 — 2 / 4
- horus-reg-srv01 — 2 / 4
- horus-pm-srv01 — 2 / 2
- horus-ans-srv01 — 1 / 1
- horus-iam-srv01 — 2 / 2
- horus-gg-srv01 — 2 / 2

The AI workload remains on node02 because `storage-ai` is node02-local.

### node03 — factory / stateful core

- horus-git-srv01 — 2 / 2
- horus-vlt-srv01 — 2 / 2
- horus-db-srv01 — 2 / 4
- horus-wiki-srv01 — 1 / 1
- horus-retro-srv01 — 1 / 2
- horus-lb-srv01 — 2 / 2

Node03 remains the Factory Node and carries stateful core services, but the resource footprint is deliberately kept below the 16 GB RAM ceiling.

### node04 — observability / storage / HAOS

- horus-grf-srv01 — 1 / 1
- horus-lok-srv01 — 2 / 2
- horus-otel-srv01 — 1 / 1
- horus-s3-srv01 — 2 / 2
- horus-ai-srv04 — 4 / 4
- horus-haos-srv01 — 2 / 4

`storage-logs` is currently reported disabled by Proxmox and must be enabled before the MinIO data mount is used.

## Special cases

- VM template 9000 remains the Debian 13 Golden VM for normal VMs.
- LXC template 9100 remains the Debian 13 Golden LXC.
- Home Assistant OS does **not** use Debian template 9000. `haos_template_id` must point to a prepared HAOS VM template on Factory Node. Until then the HAOS module is disabled.
- Root disks use `local-lvm` on every node. Large application data is attached explicitly from the real shared/local datastores.
- Terraform Bootstrap does not install GPU drivers or modify kernels. GPU enablement remains a host-level/manual concern.
