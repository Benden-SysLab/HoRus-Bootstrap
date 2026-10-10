# HoRus-Bootstrap backlog

The four-node Terraform bootstrap, 29-workload inventory (22 LXC and 7 VM), Golden 9000/9001
model, provider-native VM lifecycle, two-phase LXC placement and idempotent
steady state are complete.

Real network, NFS and physical-path coordinates are intentionally kept in the
ignored `terraform.tfvars`; the tracked topology retains the full HoRus
inventory, placement and logical storage ownership model.

## Future work

- [ ] Design an optional pool of immutable Golden LXC replicas/clone lanes for
  parallel first bootstrap. Additional template VMIDs require explicit
  approval and are not part of the current topology.
- [ ] Implement the Ansible/service layer for packages, services, application
  users, data ownership and guest-level NFS mounts derived from Terraform
  metadata, including GitGuardian CLI/ggshield, TruffleHog, Trivy, schedules,
  credentials and CI integration on `horus-gg-srv01`.
- [ ] Review long-term `local-lvm` capacity for the accepted thin-provisioning
  overcommit on Node01, Node02, Node03 and Node04; Node01 is approximately
  1.07x (140 GiB logical on 130.27 GiB physical); do not reduce approved workload sizes
  silently.
- [ ] Add CI execution for formatting, validation, Terraform tests and offline
  placement tests when a suitable secret-free runner workflow is approved.

## Explicitly out of scope

- Application configuration inside workloads.
- Automatic creation of external Golden templates 9000/9001.
- Unapproved Golden replicas or hidden clone retry/scheduler logic.
