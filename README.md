# HoRus-Bootstrap

Terraform bootstrap for the rebuilt four-node HoRus Proxmox cluster. The only
authoritative workload inventory is [`local.workloads`](topology.tf): 28
workloads (21 LXC and 7 VM), with their VMIDs, final nodes, compute, networks,
root sizes and storage ownership.

The provider is pinned to `bpg/proxmox 0.115.0`. Golden VMIDs 9000 and 9001 are
external prerequisites: this repository does not create, import, update or
destroy them.

## Provisioning model

The root module contains two workload loops:

```text
local.workloads
  -> module.lxc_containers (for_each)
  -> module.virtual_machines (for_each)
```

VM lifecycle is provider-native:

```text
Golden VM 9000 on Node03/local-lvm
  -> full clone with migrate=true
  -> final target_node/local-lvm
  -> Cloud-Init network and DNS
  -> started
```

The Golden VM already contains the approved users and SSH keys, so Terraform
does not define `user_account`, passwords or guest SSH keys.

LXC lifecycle uses the shortest supported path:

```text
Golden LXC 9001 on Node03/shared storage-infra
  -> stopped full clone directly on final target_node/storage-infra
  -> provider-owned configuration and private mount points
  -> same-node rootfs move to local-lvm
  -> upward-only resize to requested size
  -> final verification and start; start_on_boot=true
```

In `bpg/proxmox 0.115.0`, `clone.datastore_id` is the clone target storage. The
source and clone target must be shared for a cross-node LXC clone; Proxmox
9.2.21 rejects a direct target of non-shared `local-lvm`. One minimal
`terraform_data.placement` helper therefore performs only same-node rootfs
`move-volume`, upward-only resize, final verification and start. It never
migrates a CT between nodes. CPU, RAM, network, hostname, features,
unprivileged state and private mount points remain provider-owned.

The narrow lifecycle boundary ignores only `started`,
`disk[0].datastore_id`, and `disk[0].size`: the helper owns those final runtime
and rootfs placement fields. Whenever the barrier runs, it validates desired
final node, `local-lvm`, requested size, network and private mounts. Refreshed
disk/mount/start drift retriggers it; unexpected storage fails hard and
shrinking is forbidden.

## Concurrency boundary

VM clones, independent storage resources and unrelated configuration may run
with Terraform parallelism 5. LXC clones from Golden CT 9001 may not overlap:
Proxmox places `lock: disk` on source CT 9001 for the full duration of every
clone. Changing the destination storage does not remove that source lock, and
provider 0.115.0 has no keyed clone mutex or retry setting.

Terraform cannot express a per-template mutex between dynamic `for_each` module
instances. Consequently, a fresh or replacement-heavy rollout with the single
approved Golden 9001 must use `terraform apply -parallelism=1`. After the
initial bootstrap, routine changes may use `terraform apply -parallelism=5`.
Additional immutable Golden replicas could form future parallel clone lanes,
but require explicit approval; this repository does not create VMIDs 9002+.

## Storage boundaries

Private service state uses Proxmox-managed storage-backed LXC mount points, not
arbitrary host bind mounts. Terraform declares directory storages only for the
already-mounted ext4 roots on their physical owner nodes:

| Storage | Owner | Existing physical root |
|---|---|---|
| `guardian-data` | Node01 | `/srv/example/guardian-data` |
| `mimir-data` | Node02 | `/srv/example/mimir-data` |
| `artifacts-data` | Node03 | `/srv/example/artifacts` |
| `logs-data` | Node04 | `/srv/example/logs` |

`create_base_path = false` prevents Terraform from fabricating a missing root.
The existing shared Proxmox storage `storage-infra` is reused for Node03 private
volumes and Golden 9001; Terraform does not recreate it. Before an apply, every
physical root must still be verified as the intended mounted filesystem.

Shared media and build artifacts are only emitted as guest-NFS metadata for the
later Ansible layer. Terraform does not mount NFS inside guests, alter shared
UID/GID ownership, or use custom LXC idmaps. Guardian AI (VMID 104) receives no
Guardian PostgreSQL raw-data volume.

Terraform owns Proxmox object identity and infrastructure configuration.
Ansible owns packages, services, application users, application data ownership
inside guests and guest-level NFS mounts.

## Network and security

Gateways are derived centrally from the VLAN map in `topology.tf`; no global
workload gateway exists. All LXC workloads remain unprivileged. Golden template
users and SSH keys are preserved; no root-access key, password, blanket
`NOPASSWD`, privileged LXC, recursive `chown` or permissive `chmod` is added.

## State and safe checks

[`moved.tf`](moved.tf) contains one address-only move for the real existing LXC
VMID 101. It does not map historical resources by hostname and does not conceal
a VMID or type change.

```powershell
terraform fmt -recursive
terraform fmt -check -recursive
terraform validate
terraform test
pwsh -NoProfile -File tests/lxc_placement.tests.ps1
terraform plan -parallelism=1
```

Always review the plan before any apply. Use parallelism 1 for a bulk LXC
bootstrap/replacement plan; CLI parallelism 5 does not serialize the 9001 lock
domain. The capacity output deliberately shows
thin-provisioning overcommit on Node02, Node03 and Node04; approved sizes are not
silently reduced.

Implementation references:
[bpg/proxmox v0.115.0](https://github.com/bpg/terraform-provider-proxmox/tree/v0.115.0),
[Proxmox `pct`](https://pve.proxmox.com/pve-docs/pct.1.html).
