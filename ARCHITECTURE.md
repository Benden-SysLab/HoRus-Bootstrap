# HoRus-Bootstrap architecture

Environment-specific management/workload addresses, VLAN CIDRs and gateways, NFS endpoints and physical/guest paths are mandatory inputs supplied through the ignored `terraform.tfvars`. The tracked topology retains identities, placement, VLAN IDs and storage ownership.

## Design authority

The current working-tree Terraform and the verified deployment are the source
of truth. [`topology.tf`](topology.tf) declares nodes, VLANs, gateways, Golden
metadata, workloads and storage consumers exactly once. `main.tf` derives
`for_each` VM and LXC module instances; scripts do not contain a second workload
inventory.

The converged cluster contains 28 managed workloads: 21 LXC and 7 VM.

| Final node | VMID range | LXC | VM | Total |
|---|---:|---:|---:|---:|
| `horus-pmx-node01` | 101-107 | 4 | 3 | 7 |
| `horus-pmx-node02` | 201-209 | 7 | 2 | 9 |
| `horus-pmx-node03` | 301-306 | 4 | 2 | 6 |
| `horus-pmx-node04` | 401-406 | 6 | 0 | 6 |
| **Total** |  | **21** | **7** | **28** |

VMID 307 is reserved. Golden VMIDs 9000 and 9001 are external prerequisites
and remain outside Terraform state.

## Ownership boundaries

Terraform/provider owns:

- workload existence, VMID and hostname;
- CPU and RAM;
- final node and clone identity;
- network interface, VLAN, address, gateway and DNS input;
- VM/LXC feature configuration and unprivileged LXC state;
- private Proxmox mount-point declarations;
- boot policy.

Terraform also declares the approved Proxmox directory storage resources over
already-mounted physical roots. It does not create those filesystems.

Ansible and service automation own guest packages, services, application
accounts, application-level permissions, data ownership inside guests and
guest-level NFS mounts. Bootstrap intentionally stops at the infrastructure
boundary.

## VM provisioning

Golden VM 9000 is an external Debian 13 template on
`horus-pmx-node03/local-lvm` with a 12 GiB root disk. The
`proxmox_virtual_environment_vm` resource performs a full clone with
`migrate = true`, places the VM on its final node and `local-lvm`, grows the
root disk to the requested size, applies network/DNS initialization and leaves
the VM running with `on_boot = true`.

The VM path is fully provider-native. It has no placement helper. Cloud-Init
does not overwrite users or SSH keys from the Golden security baseline.

## Why Golden LXC 9001 is shared

Golden LXC 9001 is an external unprivileged Debian 13 template on
`horus-pmx-node03/storage-infra` with an 8 GiB rootfs. Proxmox requires shared
target storage for a cross-node container clone. A direct clone to another
node's non-shared `local-lvm` is rejected with:

```text
can't clone to non-shared storage 'local-lvm'
```

The provider must therefore clone directly onto the final node while the new
rootfs remains on shared `storage-infra`. The container stays stopped until
local placement is complete.

## Two-phase LXC placement

```text
provider full clone of 9001
  -> final node / storage-infra / stopped
  -> terraform_data placement barrier
  -> same-node pct move-volume rootfs local-lvm
  -> upward-only pct resize when required
  -> final-state verification
  -> pct start
  -> final node / local-lvm / requested size / running / onboot=1
```

`bpg/proxmox 0.115.0` cannot represent the required in-place LXC rootfs move
from shared storage to node-local storage without a replacement. The minimal
PowerShell helper covers only that gap. It receives its manifest from Terraform
JSON and does not invent topology.

The helper is fail-closed and idempotent:

- verifies VMID, hostname, LXC type, final node and unprivileged state;
- verifies network, VLAN, IP, gateway, features and private mounts;
- accepts rootfs only on expected `storage-infra` or final `local-lvm`;
- never performs cross-node migration;
- grows disks only when actual size is below desired size and never shrinks;
- never removes a Proxmox lock automatically;
- starts the CT only after final node/storage/size checks pass;
- performs no mutation when the CT is already correct and running.

The placement barrier is ordered after the LXC resource. Its replacement
triggers contain only the stable desired placement specification and helper
implementation hashes. Runtime provider values are deliberately excluded.
A real LXC replacement still retriggers placement through
`replace_triggered_by`.

## Intentional lifecycle boundary

The LXC resource has exactly three `ignore_changes` entries:

| Field | Reason |
|---|---|
| `started` | Provider creates the CT stopped; helper starts it after verified placement. |
| `disk[0].datastore_id` | Desired final storage is `local-lvm`, but helper performs the required in-place move after a shared-storage clone. |
| `disk[0].size` | Helper grows rootfs after the move and refuses shrinking. |

This boundary does not hide node, identity, clone, network, feature or private
mount drift. Terraform desired final state remains the final target node,
`local-lvm`, requested root size and running service. The helper reconciles and
verifies only the fields that provider 0.115.0 cannot transition safely.

Directory-backed private mounts use provider-canonical `size = "0T"` at the
resource boundary because Proxmox reads zero-sized managed volumes back in that
form. The topology retains semantic size `"0"`.

## State convergence

The helper is a completion barrier, not a parallel source of topology. Stable
desired triggers prevent refresh-only provider values from causing inconsistent
final plans or perpetual helper replacement. Provider state ignores only the
three externally completed runtime/rootfs fields, while the helper validates
their actual final state.

After the completed rollout, the normal read/refresh path was verified with:

```text
terraform plan -parallelism=5
No changes. Your infrastructure matches the configuration.
```

This proves convergence for the currently deployed bootstrap architecture.

## Clone lock and parallelism

Proxmox places `lock: disk` on source CT 9001 during every clone. The lock is on
the source template, not the destination node or datastore. Multiple concurrent
clones from the single 9001 are therefore unsafe and can fail with
`CT is locked (disk)`.

Terraform dynamic module instances have no provider-level keyed mutex, and
provider 0.115.0 supplies no per-template clone lock. Consequently:

- first bootstrap or mass LXC recreation uses `-parallelism=1`;
- steady-state independent operations may use `-parallelism=5`;
- a plan containing multiple LXC create/replace actions from 9001 must use
  parallelism 1;
- five simultaneous LXC clones would require an explicitly approved pool of
  immutable Golden replicas/clone lanes.

No static dependency chain, shell scheduler or hidden retry loop is used.

## Storage ownership

Private data is single-consumer service state. Terraform attaches it through
Proxmox-managed storage-backed LXC mount points on the physical owner node.

| Datastore | Physical owner | Existing root | Consumers |
|---|---|---|---|
| `guardian-data` | Node01 | `/private/environment/path` | Guardian PostgreSQL |
| `mimir-data` | Node02 | `/private/environment/path` | Mimir, AI PostgreSQL, Qdrant |
| `storage-infra` | Node03 | `/private/environment/path` | infrastructure PostgreSQL, Wiki, Gitea; also Golden 9001 clone storage |
| `artifacts-data` | Node03 | `/private/environment/path` | OCI Registry |
| `logs-data` | Node04 | `/private/environment/path` | MinIO |

Terraform sets `create_base_path = false` for managed directory storages, so a
missing physical mount is not silently replaced by an ordinary directory.
`storage-infra` already exists and is reused rather than recreated.

Shared media and build artifacts are a separate category. Terraform emits
their consumer metadata, while Ansible/service automation later configures NFS
inside guests. Private database trees are never documented or exposed as shared
datasets. Guardian AI receives no raw Guardian PostgreSQL files.

The approved local-LVM model is thin-provisioned and overcommitted on Node02,
Node03 and Node04. Capacity accounting is asserted in Terraform and documented
in [RESOURCE_PLAN.md](RESOURCE_PLAN.md); sizes are not silently reduced.

## Network segmentation

Management uses `private` with gateway `private`. Workload traffic is
segmented across VLANs 101, 110, 120, 130, 140, 150, 160, 170 and 180 on
`vmbr0`. Each workload's IP must belong to the selected VLAN subnet, and its
gateway is derived from the same central map. Terraform checks these invariants.

Kubernetes Pod and Service CIDRs are environment-specific and intentionally
not published here.

## Security model

Golden guests have root SSH disabled. `abbenden-srv` authenticates with an SSH
key and uses password-protected sudo without blanket `NOPASSWD`.
`jenkins-srv` authenticates with an SSH key and has no broad sudo permission.
All containers are unprivileged.

The placement helper connects to Proxmox nodes, not workload guests. It uses an
operator-supplied key file path, batch mode and strict host-key checking. No
private-key content or guest password belongs in Terraform configuration or
state.

## Safety invariants

- Golden 9000 and 9001 are never Terraform-managed.
- VMID 307 remains reserved.
- Unexpected identity, node, storage, lock or network state fails closed.
- Disk shrinking and automatic guest unlock are forbidden.
- Physical storage roots must be mounted and verified before apply.
- State commands must not conceal real VMID or type replacement.
