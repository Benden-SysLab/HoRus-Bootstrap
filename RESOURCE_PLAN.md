# HoRus resource and capacity plan

Authoritative topology: 28 workloads, 22 LXC and 6 VM. Node totals are
8 / 9 / 5 / 6. LXC roots must be at
least the Golden 9001 baseline of 8 GiB; VM roots must be at least the Golden
9000 baseline of 12 GiB. Grafana VMID 401 remains valid at 10 GiB.

## local-lvm capacity

Logical allocation is not immediate physical consumption, but the maximum
filled roots exceed physical capacity on all four nodes.

| Node | Physical local-lvm GiB | Workload roots GiB | External Golden GiB | Accounted logical GiB | Ratio |
|---|---:|---:|---:|---:|---:|
| Node01 | 130.27 | 140 | 0 | 140 | 1.07x |
| Node02 | 49.34 | 136 | 0 | 136 | 2.76x |
| Node03 | 53.93 | 72 | 12 (VM 9000) | 84 | 1.56x |
| Node04 | 53.93 | 78 | 0 | 78 | 1.45x |

Node01 now has a small reviewed thin-provisioning overcommit. Its eight
workloads allocate 20 vCPU and 26 GiB RAM. The configuration reports this
thin-provisioning risk and does not resize
approved workloads to hide it. No root has been moved to `storage-infra` as a
capacity workaround; any such change requires explicit approval.

## Persistent storage

Private owners:

- Guardian PostgreSQL -> `guardian-data`, Node01;
- Mimir state/PostgreSQL/Qdrant -> `mimir-data`, Node02;
- infrastructure PostgreSQL 17, VMID 301 -> adopted existing
  `pg-local:301/subvol-301-disk-0.subvol`, Node03-local directory datastore;
- Wiki/Gitea -> existing `storage-infra`, Node03;
- OCI Registry -> `artifacts-data`, Node03;
- MinIO -> `logs-data`, Node04.

Shared guest-NFS consumers:

- CasaOS and Joyfilm -> media export;
- CI/build agent -> artifacts build export.

Guardian AI has no Guardian PostgreSQL raw-data volume. Shared trees are not
re-owned by Terraform.

PostgreSQL keeps its root on `local-lvm`, mounts the adopted volume at
`/srv/horus/infra/postgres`, and uses
`/srv/horus/infra/postgres/17/main` as `PGDATA`. `storage-infra` is the shared
NFS datastore and is not the target for this PostgreSQL volume.

## Security scanner ownership

`horus-gg-srv01` is VMID 108, an LXC on Node01/VLAN 150 with 2 vCPU, 2 GiB RAM
and a 16 GiB local root. Terraform creates and places it, moves the rootfs to
`local-lvm`, starts it and enables `start_on_boot`. Ansible/service automation
installs GitGuardian CLI/ggshield, TruffleHog and Trivy and configures schedules,
credentials and CI integration. Scanner caches are local and temporary.
