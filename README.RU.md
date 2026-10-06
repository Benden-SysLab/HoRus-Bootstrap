# HoRus-Bootstrap

Terraform-bootstrap обновлённого четырёхнодового кластера HoRus Proxmox VE.
Репозиторий управляет 28 workloads: 21 непривилегированным LXC-контейнером и
7 виртуальными машинами, включая их размещение, вычислительные ресурсы, сеть и
подключение приватных хранилищ.

English documentation: [README.md](README.md). Подробная архитектура:
[ARCHITECTURE.md](ARCHITECTURE.md).

## Статус

Текущая топология развёрнута и приведена к сходящемуся состоянию. После
завершённого bootstrap команда `terraform plan -parallelism=5` вернула:

```text
No changes. Your infrastructure matches the configuration.
```

Это подтверждает согласованность Terraform state, ресурсов provider, LXC
placement helper и фактической конфигурации Proxmox. Используется фиксированная
версия `bpg/proxmox 0.115.0`.

## Обзор архитектуры

[`topology.tf`](topology.tf) — единственный inventory workloads. Корневой модуль
формирует из него два динамических набора модулей:

```text
local.workloads
  +-- module.virtual_machines (for_each)
  `-- module.lxc_containers   (for_each)
```

Terraform отвечает за идентичность и инфраструктурное размещение. Будущий слой
Ansible/сервисной конфигурации отвечает за пакеты, сервисы, пользователей
приложений, ownership данных внутри guests и guest-level mounts общих данных.

## Физический кластер

| Node | Management | CPU | RAM | Основная роль | Persistent roots |
|---|---|---|---:|---|---|
| `horus-pmx-node01` | `192.0.2.11` | Xeon E3-1275v2 | ~31 GiB | Guardian/security, CI, load balancing, CasaOS/media, Kubernetes worker | `/srv/example/guardian-data` |
| `horus-pmx-node02` | `192.0.2.12` | Xeon E3-1275v2, RTX 3060 12 GB | ~31 GiB | Mimir AI, Ansible, Authentik, Joyfilm, Kubernetes | `/srv/example/mimir-data` |
| `horus-pmx-node03` | `192.0.2.13` | i7-3770K | ~15.6 GiB | Storage, Golden factory, core infrastructure | `/srv/example/storage`, `/srv/example/media`, `/srv/example/artifacts`, `/srv/example/infra`, `/srv/example/camera` |
| `horus-pmx-node04` | `192.0.2.14` | i5-4210U | ~15.5 GiB | Observability, System Guardian | `/srv/example/logs` |

Management-сеть: `192.0.2.0/24`. Gateway `horus-gw-node01`:
`192.0.2.1`.

## Сеть

Все workloads используют bridge `vmbr0`. Gateway выбирается по центральной
карте VLAN; общего gateway для всех workloads нет.

| VLAN | Имя | Подсеть | Gateway |
|---:|---|---|---|
| 101 | INFRA | `198.51.100.0/28` | `198.51.100.1` |
| 110 | TRUSTED | `198.51.100.16/28` | `198.51.100.17` |
| 120 | IOT | `198.51.100.32/28` | `198.51.100.33` |
| 130 | QUARANTINE | `198.51.100.48/28` | `198.51.100.49` |
| 140 | STORAGE | `198.51.100.64/28` | `198.51.100.65` |
| 150 | OBS/SEC | `198.51.100.80/28` | `198.51.100.81` |
| 160 | AI | `198.51.100.96/28` | `198.51.100.97` |
| 170 | DMZ | `198.51.100.112/28` | `198.51.100.113` |
| 180 | K8S-LAB | `198.51.100.128/28` | `198.51.100.129` |

Для Kubernetes зарезервированы Pod CIDR `198.51.100.0/24` и Service CIDR
`203.0.113.0/24`.

## Inventory workloads

| Node | VMID | Тип | Hostname | Адрес | VLAN |
|---|---:|---|---|---|---:|
| Node01 | 101 | LXC | `horus-lb-srv01` | `198.51.100.114` | 170 |
| Node01 | 102 | LXC | `horus-agent-srv01` | `198.51.100.2` | 101 |
| Node01 | 103 | VM | `horus-jnk-srv01` | `198.51.100.3` | 101 |
| Node01 | 104 | LXC | `horus-ai-srv01` | `198.51.100.82` | 150 |
| Node01 | 105 | LXC | `horus-db-srv01` | `198.51.100.83` | 150 |
| Node01 | 106 | VM | `horus-media-srv01` | `198.51.100.4` | 101 |
| Node01 | 107 | VM | `horus-k8sw-srv01` | `198.51.100.130` | 180 |
| Node02 | 201 | LXC | `horus-ans-srv01` | `198.51.100.5` | 101 |
| Node02 | 202 | LXC | `horus-ai-srv02` | `198.51.100.98` | 160 |
| Node02 | 203 | LXC | `horus-db-srv02` | `198.51.100.99` | 160 |
| Node02 | 204 | LXC | `horus-vec-srv01` | `198.51.100.100` | 160 |
| Node02 | 205 | LXC | `horus-cache-srv01` | `198.51.100.101` | 160 |
| Node02 | 206 | LXC | `horus-iam-srv01` | `198.51.100.6` | 101 |
| Node02 | 207 | LXC | `horus-media-srv02` | `198.51.100.7` | 101 |
| Node02 | 208 | VM | `horus-k8sw-srv02` | `198.51.100.131` | 180 |
| Node02 | 209 | VM | `horus-k8sc-srv01` | `198.51.100.132` | 180 |
| Node03 | 301 | LXC | `horus-db-srv03` | `198.51.100.8` | 101 |
| Node03 | 302 | VM | `horus-vlt-srv01` | `198.51.100.9` | 101 |
| Node03 | 303 | LXC | `horus-wiki-srv01` | `198.51.100.10` | 101 |
| Node03 | 304 | LXC | `horus-git-srv01` | `198.51.100.11` | 101 |
| Node03 | 305 | VM | `horus-work-srv01` | `198.51.100.12` | 101 |
| Node03 | 306 | LXC | `horus-reg-srv01` | `198.51.100.13` | 101 |
| Node04 | 401 | LXC | `horus-grf-srv01` | `198.51.100.84` | 150 |
| Node04 | 402 | LXC | `horus-pm-srv01` | `198.51.100.85` | 150 |
| Node04 | 403 | LXC | `horus-lok-srv01` | `198.51.100.86` | 150 |
| Node04 | 404 | LXC | `horus-otel-srv01` | `198.51.100.87` | 150 |
| Node04 | 405 | LXC | `horus-s3-srv01` | `198.51.100.88` | 150 |
| Node04 | 406 | LXC | `horus-ai-srv03` | `198.51.100.89` | 150 |

Количество по нодам: 7 / 9 / 6 / 6. VMID 307 зарезервирован и Terraform его
не создаёт.

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

| Сервис/данные | Владелец | Host root / guest path |
|---|---|---|
| Guardian PostgreSQL | Node01 / `horus-db-srv01` | `/srv/example/guardian-data` |
| Mimir | Node02 / `horus-ai-srv02` | `/srv/example/mimir-data` |
| AI PostgreSQL | Node02 / `horus-db-srv02` | `/srv/example/mimir-data/postgres` |
| Qdrant | Node02 / `horus-vec-srv01` | `/srv/example/mimir-data/vectors` |
| Infrastructure PostgreSQL | Node03 / `horus-db-srv03` | `/srv/example/infra/postgres` |
| Wiki | Node03 / `horus-wiki-srv01` | `/srv/example/infra/wiki` |
| Gitea | Node03 / `horus-git-srv01` | `/srv/example/infra/gitea` |
| OCI Registry | Node03 / `horus-reg-srv01` | `/srv/example/artifacts/registry` |
| MinIO | Node04 / `horus-s3-srv01` | `/srv/example/logs` |

Terraform объявляет `guardian-data`, `mimir-data`, `artifacts-data` и
`logs-data` только поверх уже смонтированных физических roots и использует
`create_base_path = false`. Существующий `storage-infra` обслуживает Golden
9001 и private volumes Node03. Guardian AI не получает raw PostgreSQL files.

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
