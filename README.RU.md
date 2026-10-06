# HoRus-Bootstrap

Terraform-bootstrap четырёхнодового кластера HoRus Proxmox. Единственный
авторитетный inventory — `local.workloads` в [topology.tf](topology.tf):
28 workloads, из них 21 LXC и 7 VM.

Provider зафиксирован на `bpg/proxmox 0.115.0`. Golden VMID 9000 и 9001 —
внешние prerequisites; Terraform их не создаёт, не импортирует, не изменяет и
не удаляет.

## Жизненный цикл

- VM: full clone Golden 9000 с Node03/local-lvm, provider-native migration на
  `target_node/local-lvm`, Cloud-Init только для сети/DNS, затем запуск и
  `on_boot = true`.
- LXC: full clone Golden 9001 с Node03/shared `storage-infra` сразу на
  финальную ноду, но с rootfs на shared `storage-infra`; provider применяет
  конфигурацию и private mount points, затем минимальный helper на той же ноде
  переносит rootfs в `local-lvm`, увеличивает только вверх, проверяет и запускает
  CT. `start_on_boot = true` задаёт provider.

В корне осталось только два `for_each`-модуля. В provider 0.115.0 поле
`clone.datastore_id` означает целевое хранилище clone, но Proxmox 9.2.21
запрещает cross-node clone прямо в non-shared `local-lvm`. Поэтому оставлен один
минимальный completion barrier: same-node `pct move-volume`, resize только
вверх, итоговая проверка и start. `pct migrate` отсутствует.

`ignore_changes` ограничен `started`, `disk[0].datastore_id` и
`disk[0].size`: только этими полями после clone владеет helper. Node, clone
identity, CPU/RAM, network, hostname, features и private mounts не игнорируются.

## Параллелизм

VM clone, независимые storage resources и несвязанные изменения могут идти с
Terraform parallelism 5. Но каждый LXC clone ставит `lock: disk` на исходный CT
9001 на всё время копирования. Целевые node/storage на этот lock не влияют;
одновременные clones от одного Golden 9001 небезопасны.

Terraform и provider 0.115.0 не умеют задать per-template mutex для динамических
экземпляров `for_each`. Поэтому массовый первый rollout или массовая замена LXC
с единственным 9001 не могут безопасно выполняться одним
`terraform apply -parallelism=5`. Parallelism 5 безопасен, когда план содержит
не более одного LXC create/replace. Текущий массовый bootstrap выполняется
`terraform apply -parallelism=1`; после него обычные изменения могут идти с
`-parallelism=5`. Дополнительные Golden replicas/clone lanes требуют отдельного
согласования; VMID 9002+ этот репозиторий не создаёт.

## Хранилища и безопасность

Private state создаётся как Proxmox-managed storage-backed mount point на
физическом owner root. `create_base_path = false`; существующие ext4 mountpoints
нужно проверить перед apply. Существующий `storage-infra` не пересоздаётся.

Общие `media` и build artifacts представлены только metadata для guest-level
NFS, который позже настраивает Ansible. Terraform не делает host bind mount,
не угадывает UID/GID и не меняет ownership shared trees. Guardian AI VMID 104
не получает raw Guardian PostgreSQL files.

Все LXC остаются unprivileged. Пользователи и SSH-ключи уже находятся в Golden;
Terraform не передаёт guest password, `user_account` или root SSH key.

## State и проверки

[moved.tf](moved.tf) содержит только address-only move реально существующего
LXC VMID 101. Исторические объекты по hostname не сопоставляются.

```powershell
terraform fmt -recursive
terraform fmt -check -recursive
terraform validate
terraform test
pwsh -NoProfile -File tests/lxc_placement.tests.ps1
terraform plan -parallelism=1
```

Если план содержит несколько LXC create/replace, его запускают только с
parallelism 1. После bootstrap независимые изменения допускают parallelism 5.

Вывод `local_lvm_capacity` явно показывает thin-provisioning overcommit на
Node02/03/04; утверждённые размеры workloads автоматически не уменьшаются.
