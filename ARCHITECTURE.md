# HoRus architecture

## Ownership

`topology.tf` is the single source of truth for nodes, VLANs, gateways,
workloads and storage consumers. `main.tf` derives two `for_each` module calls
from that inventory. Scripts never duplicate workload topology.

Terraform owns VM/LXC existence, VMID, hostname, CPU/RAM, root disk, final node,
VLAN/IP/gateway and Proxmox-managed private volumes. Ansible owns guest packages,
services, application accounts, application data ownership and guest NFS mounts.

## Workloads

| Final node | VMID range | LXC | VM | Total |
|---|---:|---:|---:|---:|
| `horus-pmx-node01` | 101-107 | 4 | 3 | 7 |
| `horus-pmx-node02` | 201-209 | 7 | 2 | 9 |
| `horus-pmx-node03` | 301-306 | 4 | 2 | 6 |
| `horus-pmx-node04` | 401-406 | 6 | 0 | 6 |
| **Total** |  | **21** | **7** | **28** |

VMID 307 is reserved. External Golden VMID 9000 and 9001 are outside workload
state.

## Placement

VMs use native provider clone/migration. LXC full clones are created stopped on
their final node with rootfs on shared `storage-infra`; Proxmox rejects a
cross-node clone directly to non-shared `local-lvm`. A single completion barrier
then performs the same-node rootfs move, upward-only resize, verification and
start. It never migrates the CT between nodes.

Proxmox serializes clones by locking source CT 9001 with `lock: disk`. That lock
is independent of destination node/storage. Terraform can run independent VM,
storage and configuration operations at parallelism 5 after bootstrap, but
provider 0.115.0 and Terraform have no per-template mutex for dynamic `for_each`
instances. Bulk LXC creation/replacement therefore uses global parallelism 1;
ordinary post-bootstrap changes may use parallelism 5.

## Storage

Private state is single-consumer Proxmox-managed storage-backed volume data.
Shared media/artifacts are guest-NFS metadata for Ansible. Guardian AI has no raw
Guardian database mount. No privileged LXC, custom idmap, UID/GID guessing,
recursive ownership change or host bind orchestration is used.

The physical local-lvm capacity is lower than logical roots on Node02/03/04.
See [RESOURCE_PLAN.md](RESOURCE_PLAN.md); changing root placement requires user
approval and is not hidden in this implementation.
