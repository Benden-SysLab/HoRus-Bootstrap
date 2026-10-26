# HoRus-Bootstrap

Terraform-bootstrap обновлённого четырёхнодового кластера HoRus Proxmox VE.
Репозиторий управляет 28 workloads: 22 непривилегированными LXC-контейнерами и
6 виртуальными машинами, включая их размещение, вычислительные ресурсы, сеть и
подключение приватных хранилищ.

English documentation: [README.md](README.md). Подробная архитектура:
[ARCHITECTURE.md](ARCHITECTURE.md).

## Статус

Текущее desired state развёрнуто и приведено к сходящемуся состоянию. После
удаления дублирующего Ansible-хоста и уплотнения VMID Node02
`terraform plan -parallelism=5` вернул:

```text
No changes. Your infrastructure matches the configuration.
```

Rollout v2.2.1 удалил `horus-ans-srv01` и пересоздал только утверждённые
workloads Node02, чьи VMID изменились. IAM остался работать как VMID 206;
Golden 9000/9001 не изменялись. Используется `bpg/proxmox 0.115.0`.

Ansible control tooling переносится на существующий Jenkins agent
`horus-agent-srv01`; его guest-конфигурацией управляет HoRus-Basis.

## Обзор архитектуры

[`topology.tf`](topology.tf) — единственный inventory workloads. Корневой модуль
формирует из него два динамических набора модулей:

```text
local.workloads
  +-- module.virtual_machines (for_each)
  `-- module.lxc_containers   (for_each)
```

HoRus-Bootstrap и Terraform отвечают за lifecycle инфраструктуры Proxmox,
топологию VM/LXC, storage attachments и infrastructure resources. HoRus-Basis
и Ansible отвечают за конфигурацию guest OS, пакеты и сервисы. Argo CD
предназначен только для будущего Kubernetes GitOps: он не управляет Proxmox
VM/LXC и не считается развёрнутым.

Выделенная Workspace `horus-work-srv01` выведена из desired architecture.
KasmVNC и code-server не являются активными сервисами HoRus; разработка и CAD
выполняются на личном ноутбуке оператора.

## Физический кластер

| Node | CPU | RAM | Основная роль |
|---|---|---:|---|
| `horus-pmx-node01` | Xeon E3-1275v2 | ~31 GiB | Guardian/security, CI, load balancing, CasaOS/media, Kubernetes worker |
| `horus-pmx-node02` | Xeon E3-1275v2, RTX 3060 12 GB | ~31 GiB | Mimir AI, Authentik, Joyfilm, Kubernetes |
| `horus-pmx-node03` | i7-3770K | ~15.6 GiB | Storage, Golden factory, core infrastructure |
| `horus-pmx-node04` | i5-4210U | ~15.5 GiB | Observability, System Guardian |

Management-адреса, CIDR, gateway и физические storage paths задаются как
обязательные environment-specific значения в ignored `terraform.tfvars`.

## Сеть

Все workloads используют bridge `vmbr0`. Gateway выбирается по центральной
карте VLAN; общего gateway для всех workloads нет.

| VLAN | Имя |
|---:|---|
| 101 | INFRA |
| 110 | TRUSTED |
| 120 | IOT |
| 130 | QUARANTINE |
| 140 | STORAGE |
| 150 | OBS/SEC |
| 160 | AI |
| 170 | DMZ |
| 180 | K8S-LAB |

Реальные workload IP, VLAN CIDR и gateway поступают из ignored
`terraform.tfvars`; Terraform проверяет соответствие каждой workload/VLAN пары.

Kubernetes Pod и Service CIDR относятся к environment-specific сетевому
дизайну и не публикуются в репозитории.

## Inventory workloads

| Node | VMID | Тип | Hostname | Адрес | VLAN |
|---|---:|---|---|---|---:|
| Node01 | 101 | LXC | `horus-lb-srv01` | private | 170 |
| Node01 | 102 | LXC | `horus-agent-srv01` | private | 101 |
| Node01 | 103 | VM | `horus-jnk-srv01` | private | 101 |
| Node01 | 104 | LXC | `horus-ai-srv01` | private | 150 |
| Node01 | 105 | LXC | `horus-db-srv01` | private | 150 |
| Node01 | 106 | VM | `horus-media-srv01` | private | 101 |
| Node01 | 107 | VM | `horus-k8sw-srv01` | private | 180 |
| Node01 | 108 | LXC | `horus-gg-srv01` | private | 150 |
| Node02 | 201 | LXC | `horus-ai-srv02` | private | 160 |
| Node02 | 202 | LXC | `horus-db-srv02` | private | 160 |
| Node02 | 203 | LXC | `horus-vec-srv01` | private | 160 |
| Node02 | 204 | LXC | `horus-cache-srv01` | private | 160 |
| Node02 | 205 | LXC | `horus-media-srv02` | private | 101 |
| Node02 | 206 | LXC | `horus-iam-srv01` | private | 101 |
| Node02 | 207 | VM | `horus-k8sw-srv02` | private | 180 |
| Node02 | 208 | VM | `horus-k8sc-srv01` | private | 180 |
| Node03 | 301 | LXC | `horus-db-srv03` | private | 101 |
| Node03 | 302 | VM | `horus-vlt-srv01` | private | 101 |
| Node03 | 303 | LXC | `horus-wiki-srv01` | private | 101 |
| Node03 | 304 | LXC | `horus-git-srv01` | private | 101 |
| Node03 | 305 | LXC | `horus-reg-srv01` | private | 101 |
| Node03 | 306 | LXC | `horus-vkj-srv01` | private | 101 |
| Node04 | 401 | LXC | `horus-grf-srv01` | private | 150 |
| Node04 | 402 | LXC | `horus-pm-srv01` | private | 150 |
| Node04 | 403 | LXC | `horus-lok-srv01` | private | 150 |
| Node04 | 404 | LXC | `horus-otel-srv01` | private | 150 |
| Node04 | 405 | LXC | `horus-s3-srv01` | private | 150 |
| Node04 | 406 | LXC | `horus-ai-srv03` | private | 150 |

Количество по нодам: 8 / 9 / 6 / 6. Node01 использует VMID 101-108. VMID 307
зарезервирован, Terraform его не создаёт. Registry задан как
`horus-reg-srv01`, VMID 305 (ранее 306), на `horus-pmx-node03`, адрес
`10.10.1.36/24`, VLAN 101, root на `local-lvm`, persistent storage
`artifacts-data`. Controlled replacement выполнен ранее и теперь подтверждён
сходящимся refreshed plan.

`horus-vkj-srv01` — отдельный LXC приложения Vikunja на Node03/VLAN 101.
Terraform владеет VMID 306, compute, сетью, placement, boot policy и приватным
подключением `infra-data`. HoRus-Basis/Ansible отвечает за Vikunja, настройку
его БД и lifecycle приложения; PostgreSQL предоставляется DB03.

`horus-gg-srv01` — изолированный security scanner для GitGuardian CLI/ggshield,
TruffleHog и Trivy. Terraform создаёт LXC, задаёт VMID, CPU, RAM, сеть и
placement, переносит rootfs в `local-lvm`, запускает контейнер и включает
`start_on_boot`. Ansible/service automation устанавливает и настраивает
сканеры, расписание, credentials и интеграцию с CI. На Node01 выделено 20 vCPU,
26 GiB RAM и 140 GiB logical workload roots при 130.27 GiB физического
`local-lvm`: утверждённый небольшой thin-provisioning overcommit около 1.07x.

## Golden templates

Golden templates являются внешними prerequisites и не входят в Terraform
state. Terraform не должен создавать, импортировать, заменять или удалять их.

| VMID | Тип | Размещение | Базовый root | Свойства |
|---:|---|---|---:|---|
| 9000 | Debian 13 VM | Node03 / `local-lvm` | 12 GiB | источник VM clones |
| 9001 | Debian 13 LXC | Node03 / `storage-infra` | 8 GiB | unprivileged, shared clone source |

### Жизненный цикл VM

VM создаются полностью средствами provider:

```text
Golden 9000 на Node03/local-lvm
  -> full clone с migrate=true
  -> финальная node/local-lvm
  -> requested disk size и Cloud-Init network/DNS
  -> started=true и on_boot=true
```

Для VM внешние placement scripts не используются.

### Жизненный цикл LXC

Cross-node LXC clone в Proxmox требует shared target storage. Прямой clone с
Node03 в non-shared `local-lvm` другой ноды завершается ошибкой
`can't clone to non-shared storage 'local-lvm'`. Поэтому используется следующий
lifecycle:

```text
Golden 9001 на Node03/storage-infra
  -> provider full clone
  -> финальная node/storage-infra, stopped
  -> same-node placement helper
  -> pct move-volume rootfs в local-lvm
  -> grow rootfs только при необходимости
  -> проверка identity, node, storage, size, mounts и network
  -> pct start
  -> running с onboot=1
```

Helper не выполняет межнодовую миграцию контейнеров. Он идемпотентен, никогда
не уменьшает диски и жёстко останавливается при неожиданном identity, node,
storage, lock, network или mount configuration.

Provider владеет existence, VMID, hostname, CPU, RAM, final node, clone
identity, network, VLAN, IP, gateway, features, unprivileged state, private
mount declarations и `start_on_boot`. Helper владеет только неизбежными
post-clone операциями: переносом rootfs, безопасным увеличением, финальной
проверкой и запуском.

Три точечных `ignore_changes` фиксируют эту границу:

- `started`: helper запускает CT только после проверки placement;
- `disk[0].datastore_id`: helper выполняет неподдерживаемый provider in-place
  move в финальный `local-lvm`;
- `disk[0].size`: helper увеличивает rootfs после переноса.

Это не общее подавление drift. Helper проверяет desired final state при
изменении стабильной desired specification или своей реализации.

## Модель хранилищ

Private application state — это данные одного владельца, подключённые как
Proxmox-managed LXC mount-point volumes. Они не являются shared application
data.

| Сервис/данные | Владелец | Логический datastore |
|---|---|---|
| Guardian PostgreSQL | Node01 / `horus-db-srv01` | `guardian-data` |
| Mimir, AI PostgreSQL, Qdrant | Node02 / соответствующие workloads | `mimir-data` |
| Infrastructure PostgreSQL | Node03 / `horus-db-srv03` | provider-allocated volume `pg-local` |
| Weekly backups PostgreSQL | Node03 / `horus-db-srv03` | provider-allocated volume 8 GiB на `storage-infra` |
| Wiki, Gitea, Vikunja | Node03 / соответствующие workloads | `storage-infra` |
| OCI Registry | Node03 / `horus-reg-srv01` | `artifacts-data` |
| MinIO | Node04 / `horus-s3-srv01` | `logs-data` |

Физические host paths, guest mount paths и NFS endpoints задаются через
ignored `terraform.tfvars`.

Terraform объявляет `guardian-data`, `mimir-data`, `artifacts-data` и
`logs-data` только поверх уже смонтированных физических roots и использует
`create_base_path = false`. PostgreSQL 17 на `horus-db-srv03` (VMID 301,
Node03, VLAN 101) сохраняет root на `local-lvm`. Terraform/provider выделяет
PostgreSQL volume на `pg-local` и монтирует его в
`/srv/horus/infra/postgres`; `PGDATA` —
`/srv/horus/infra/postgres/17/main`. Отдельный provider-allocated volume 8 GiB
на `storage-infra` монтируется в `/srv/horus/infra/backups`.

Clone lifecycle резервирует disk index 0 на `storage-infra` под временный
rootfs, поэтому backup использует отдельный
`storage-infra:301/vm-301-disk-1.raw`. Guardian AI не получает raw PostgreSQL
files.

Shared media и build artifacts описаны отдельно как metadata для будущей
guest-level NFS configuration. Bootstrap не настраивает приложения, не
монтирует NFS внутри guests, не придумывает UID/GID и не меняет ownership
shared trees.

## Security model

В Golden baseline отключён root SSH внутри guests. `abbenden-srv` использует
SSH key и sudo с паролем; blanket `NOPASSWD` отсутствует. `jenkins-srv`
использует SSH key и не имеет широкого sudo. Все LXC — unprivileged.

Оператор передаёт только локальный путь к key-файлу для подключения placement
helper к Proxmox nodes. Credentials, содержимое private keys и пароли нельзя
добавлять в репозиторий.

## Prerequisites и configuration

- доступный четырёхнодовый Proxmox VE cluster и API endpoint;
- внешние Golden templates 9000 и 9001 в указанных хранилищах;
- проверенные physical storage mounts и существующий `storage-infra`;
- Terraform, PowerShell 7 и OpenSSH client на машине оператора;
- API credentials с необходимыми правами на guests/storage;
- root SSH по ключу к Proxmox nodes с проверенными host keys.

Скопируйте `terraform.tfvars.example` в локальный игнорируемый
`terraform.tfvars`, затем задайте endpoint, credentials и путь к ключу
оператора. Не коммитьте secrets.

## Первый bootstrap или массовое пересоздание LXC

```powershell
terraform init
terraform validate
terraform plan -parallelism=1
terraform apply -parallelism=1
```

Во время clone Proxmox ставит `lock: disk` на source CT 9001. Параллельные
clones из единственного Golden 9001 могут завершиться ошибкой
`CT is locked (disk)`. Provider 0.115.0 не предоставляет per-template mutex,
поэтому для fresh или replacement-heavy LXC rollout требуется global
parallelism 1.

## Обычная steady-state работа

```powershell
terraform plan -parallelism=5
terraform apply -parallelism=5
```

После bootstrap parallelism 5 подходит для независимых VM, storage и
configuration changes. Каждый plan нужно проверить: если он содержит несколько
LXC create/replace от source 9001, следует вернуться к parallelism 1.

## Проверки и тесты

```powershell
terraform fmt -recursive
terraform fmt -check -recursive
terraform validate
terraform test
pwsh -NoProfile -File tests/lxc_placement.tests.ps1
```

Текущий результат: 5 Terraform tests passed, 0 failed; 7 offline placement
tests passed.

## Известные ограничения

- Один Golden LXC source сериализует массовое клонирование LXC.
- Безопасные параллельные clone lanes потребуют дополнительных согласованных
  immutable Golden replicas; это future work, а не текущая инфраструктура.
- Утверждённая thin-provisioning модель допускает overcommit `local-lvm` на
  Node02, Node03 и Node04; подробнее в [RESOURCE_PLAN.md](RESOURCE_PLAN.md).
- Application provisioning и guest-level shared mounts относятся к будущему
  слою Ansible/service configuration.

## Структура репозитория

| Путь | Назначение |
|---|---|
| `topology.tf` | авторитетные nodes, VLANs, workloads и storage consumers |
| `main.tf` | storage resources и динамические VM/LXC module calls |
| `modules/proxmox_vm/` | provider-native VM lifecycle |
| `modules/proxmox_lxc/` | provider-owned LXC и placement barrier |
| `scripts/lxc_placement.ps1` | минимальная Terraform entry point для LXC placement |
| `scripts/lib/Horus.LxcPlacement.ps1` | fail-closed placement implementation |
| `tests/` | inventory, module и offline helper tests |
| `ARCHITECTURE.md` | ownership и обоснование архитектуры |
| `BACKLOG.md` | оставшиеся задачи |

## Operational safety

Всегда проверяйте `terraform plan` перед apply. Golden 9000/9001 и physical
storage mounts — внешние prerequisites. Нельзя использовать state-команды для
сокрытия реальной замены VMID/type или автоматически снимать lock с guest.

Проект распространяется по [Apache License 2.0](LICENSE). Репозиторий:
[Benden-SysLab/HoRus-Bootstrap](https://github.com/Benden-SysLab/HoRus-Bootstrap).
