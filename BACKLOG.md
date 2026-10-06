### 📋 Бэклог проекта HoRus-Bootstrap

- [x] Приведение топологии к 4-нодовому кластеру Proxmox VE (28 workloads: 21 LXC, 7 VM)
- [x] Golden LXC 9001: stopped clone to final node/shared storage-infra, then same-node rootfs move to local-lvm
- [ ] Provider-level keyed mutex for Golden 9001 clone operations (required for one-shot bulk apply with parallelism 5)
- [ ] Optional Golden replica/clone-lane design; no VMID 9002+ without explicit approval
- [x] Жизненный цикл ВМ через Full Clone Golden VM 9000 на Factory Node (`horus-pmx-node03`)
- [ ] Реализация guest-level NFS mounts из Terraform metadata в Ansible
- [ ] Capacity decision для local-lvm overcommit Node02/03/04
