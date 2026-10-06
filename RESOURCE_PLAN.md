# HoRus resource and capacity plan

Authoritative topology: 28 workloads, 21 LXC and 7 VM. LXC roots must be at
least the Golden 9001 baseline of 8 GiB; VM roots must be at least the Golden
9000 baseline of 12 GiB. Grafana VMID 401 remains valid at 10 GiB.

## local-lvm capacity

Logical allocation is not immediate physical consumption, but the maximum
filled roots exceed physical capacity on three nodes.

| Node | Physical local-lvm GiB | Workload roots GiB | External Golden GiB | Accounted logical GiB | Ratio |
|---|---:|---:|---:|---:|---:|
| Node01 | 130.27 | 124 | 0 | 124 | 0.95x |
| Node02 | 49.34 | 136 | 0 | 136 | 2.76x |
| Node03 | 53.93 | 88 | 12 (VM 9000) | 100 | 1.85x |
| Node04 | 53.93 | 78 | 0 | 78 | 1.45x |

The configuration reports this thin-provisioning risk and does not resize
approved workloads to hide it. No root has been moved to `storage-infra` as a
capacity workaround; any such change requires explicit approval.

## Persistent storage

Private owners:

- Guardian PostgreSQL -> `guardian-data`, Node01;
- Mimir state/PostgreSQL/Qdrant -> `mimir-data`, Node02;
- infrastructure PostgreSQL/Wiki/Gitea -> existing `storage-infra`, Node03;
- OCI Registry -> `artifacts-data`, Node03;
- MinIO -> `logs-data`, Node04.

Shared guest-NFS consumers:

- CasaOS and Joyfilm -> media export;
- CI/build agent -> artifacts build export.

Guardian AI has no Guardian PostgreSQL raw-data volume. Shared trees are not
re-owned by Terraform.
