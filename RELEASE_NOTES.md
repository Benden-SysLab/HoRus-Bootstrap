# HoRus-Bootstrap v2.0.0 — draft release notes

Proposed release: `v2.0.0`.

No repository tags currently exist. A major version is appropriate because the
bootstrap now represents a new four-node topology, a new authoritative workload
inventory and a materially different VM/LXC provisioning lifecycle. This file
is preparation only; no tag or GitHub release has been created.

## Highlights

- Four-node HoRus Proxmox VE topology with central management and VLAN maps.
- Authoritative inventory of 28 workloads: 21 LXC containers and 7 VMs.
- External Debian 13 Golden templates:
  - VMID 9000 on Node03/`local-lvm`, 12 GiB VM baseline;
  - VMID 9001 on Node03/`storage-infra`, 8 GiB unprivileged LXC baseline.
- Provider-native VM full clone, cross-node placement, disk growth, network and
  boot policy.
- Two-phase LXC provisioning: clone stopped on the final node through shared
  `storage-infra`, then same-node rootfs move to `local-lvm`, upward-only resize,
  verification and start.
- Single-owner persistent storage model for Guardian, Mimir, AI PostgreSQL,
  Qdrant, infrastructure PostgreSQL, Wiki, Gitea, OCI Registry and MinIO.
- Segmented VLAN/gateway design on `vmbr0`, including INFRA, OBS/SEC, AI, DMZ
  and K8S-LAB workload networks.
- Provider pinned to `bpg/proxmox 0.115.0`.
- Verified converged state: steady-state plan returned
  `No changes. Your infrastructure matches the configuration.`

## Validation

- `terraform fmt -check -recursive`: passed.
- `terraform validate`: passed.
- Terraform tests: 5 passed, 0 failed.
- Offline LXC placement tests: 7 passed.

## Known limitation

Proxmox locks source CT 9001 with `lock: disk` while cloning. Multiple LXC
clones from the single Golden template must not overlap. First bootstrap and
mass LXC recreation require `terraform apply -parallelism=1`; ordinary
steady-state operations may use parallelism 5 after plan review.

Future parallel bootstrap would require an explicitly approved pool of
immutable Golden replicas/clone lanes. No additional templates are included in
this release.

## Breaking changes

- Replaces the previous topology and network addressing with the current
  four-node, VLAN-segmented inventory.
- Workloads are generated from one authoritative `for_each` inventory rather
  than duplicated resource declarations.
- VM and LXC provisioning now use external Golden templates 9000 and 9001.
- LXC rootfs placement uses the shared-clone/same-node-move lifecycle required
  by Proxmox instead of the legacy provisioning workflow.
- Gateways are derived per VLAN; no single gateway applies to all workloads.
- Private application state is modeled separately from shared media/artifact
  datasets.

Review Terraform plans and migration impact before adopting this release over
an older deployment. Golden templates and physical storage mounts remain
operator-managed prerequisites.
