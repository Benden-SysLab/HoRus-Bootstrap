# HoRus-Bootstrap

Terraform-bootstrap перебудованого чотиривузлового кластера HoRus Proxmox VE.
Репозиторій керує 29 workloads: 22 непривілейованими LXC-контейнерами і
7 віртуальними машинами.

Повна довідка: [README.md](README.md). Детальна архітектура:
[ARCHITECTURE.md](ARCHITECTURE.md). Авторитетна топологія:
[`topology.tf`](topology.tf).

Environment-specific management/workload адреси, VLAN CIDR і gateway, NFS endpoints та фізичні paths задаються лише через ignored `terraform.tfvars`.

## Стан

Поточну топологію успішно розгорнуто та приведено до збіжного стану. Після
bootstrap команда `terraform plan -parallelism=5` повернула:

```text
No changes. Your infrastructure matches the configuration.
```

Зафіксована версія provider: `bpg/proxmox 0.115.0`.

## Архітектура

`topology.tf` — єдине джерело для вузлів, VLAN, gateways, workloads і storage.
З нього створюються дві динамічні групи модулів:

```text
local.workloads
  +-- module.virtual_machines (for_each)
  `-- module.lxc_containers   (for_each)
```

Terraform відповідає за ідентичність та інфраструктурне розміщення. Ansible і
майбутній сервісний шар відповідають за пакети, сервіси, користувачів, права на
дані всередині guests і guest-level NFS mounts.

## Фізичний кластер

| Вузол | Management | Обладнання | Роль |
|---|---|---|---|
| `horus-pmx-node01` | `private` | Xeon E3-1275v2, ~31 GiB RAM | Guardian/security, CI, балансування, media, Kubernetes worker |
| `horus-pmx-node02` | `private` | Xeon E3-1275v2, ~31 GiB RAM, RTX 3060 12 GB | Mimir AI, Ansible, Authentik, Joyfilm, Kubernetes |
| `horus-pmx-node03` | `private` | i7-3770K, ~15,6 GiB RAM | storage, Golden factory, основна інфраструктура |
| `horus-pmx-node04` | `private` | i5-4210U, ~15,5 GiB RAM | observability, System Guardian |

Management-мережа: `private`, gateway `private`. Усі workloads
використовують `vmbr0`.

## Мережа

| VLAN | Назва | Підмережа | Gateway |
|---:|---|---|---|
| 101 | INFRA | `private` | `private` |
| 110 | TRUSTED | `private` | `private` |
| 120 | IOT | `private` | `private` |
| 130 | QUARANTINE | `private` | `private` |
| 140 | STORAGE | `private` | `private` |
| 150 | OBS/SEC | `private` | `private` |
| 160 | AI | `private` | `private` |
| 170 | DMZ | `private` | `private` |
| 180 | K8S-LAB | `private` | `private` |

Kubernetes: Pod CIDR `private`, Service CIDR `private`.

## Inventory workloads

| Вузол | LXC | VM | Разом |
|---|---|---|---:|
| Node01 | 101 `horus-lb-srv01`, 102 `horus-agent-srv01`, 104 `horus-ai-srv01`, 105 `horus-db-srv01`, 108 `horus-gg-srv01` | 103 `horus-jnk-srv01`, 106 `horus-media-srv01`, 107 `horus-k8sw-srv01` | 8 |
| Node02 | 201 `horus-ans-srv01`, 202 `horus-ai-srv02`, 203 `horus-db-srv02`, 204 `horus-vec-srv01`, 205 `horus-cache-srv01`, 206 `horus-iam-srv01`, 207 `horus-media-srv02` | 208 `horus-k8sw-srv02`, 209 `horus-k8sc-srv01` | 9 |
| Node03 | 301 `horus-db-srv03`, 303 `horus-wiki-srv01`, 304 `horus-git-srv01`, 306 `horus-reg-srv01` | 302 `horus-vlt-srv01`, 305 `horus-work-srv01` | 6 |
| Node04 | 401 `horus-grf-srv01`, 402 `horus-pm-srv01`, 403 `horus-lok-srv01`, 404 `horus-otel-srv01`, 405 `horus-s3-srv01`, 406 `horus-ai-srv03` | — | 6 |
| **Разом** | **22 LXC** | **7 VM** | **29** |

VMID 307 зарезервовано; Terraform його не створює.

Node01 використовує VMID 101-108. `horus-gg-srv01` (VMID 108, LXC, VLAN 150) — ізольований scanner GitGuardian CLI/ggshield, TruffleHog і Trivy. Terraform створює і розміщує LXC, переносить rootfs до `local-lvm`, запускає його та вмикає `start_on_boot`; Ansible/service automation встановлює й налаштовує scanners, розклад, credentials та CI integration. Node01: 20 vCPU, 26 GiB RAM і 140 GiB logical roots на 130.27 GiB фізичного `local-lvm` (thin provisioning ≈1.07x).

## Golden templates

| VMID | Тип | Розміщення | Базовий розмір |
|---:|---|---|---:|
| 9000 | Debian 13 VM | Node03 / `local-lvm` | 12 GiB |
| 9001 | Debian 13 LXC, unprivileged | Node03 / `storage-infra` | 8 GiB |

Обидва templates є зовнішніми prerequisites і не входять до Terraform state.

### Життєвий цикл VM

VM повністю керуються provider: full clone 9000, native migration на фінальний
вузол, `local-lvm`, потрібний розмір диска, мережа/DNS, `started=true` та
`on_boot=true`. Зовнішнього placement helper для VM немає.

### Життєвий цикл LXC

Proxmox вимагає shared storage для LXC clone між вузлами:

```text
Golden 9001 / Node03 / storage-infra
  -> full clone на фінальному вузлі / storage-infra / stopped
  -> same-node pct move-volume у local-lvm
  -> збільшення лише за потреби
  -> перевірка identity, node, storage, size, mounts і network
  -> запуск; running + onboot=1
```

Helper не мігрує контейнери між вузлами, ніколи не зменшує диски та безпечно
зупиняється за неочікуваного стану. Межа містить лише `started`,
`disk[0].datastore_id` і `disk[0].size`.

## Storage і безпека

Private data належать одному сервісу: Guardian на Node01, Mimir та AI на
Node02, infrastructure/Registry на Node03, MinIO logs на Node04. Shared media
та artifacts пізніше налаштовуються як NFS усередині guests через Ansible.
Guardian AI не отримує raw PostgreSQL files.

Root SSH вимкнено в Golden guests. `abbenden-srv` використовує SSH key і sudo
з паролем без blanket `NOPASSWD`. `jenkins-srv` не має широкого sudo. Усі LXC
непривілейовані. Credentials і private keys не можна коммітити.

## Експлуатація

Перший bootstrap або масове пересоздання LXC:

```powershell
terraform init
terraform validate
terraform plan -parallelism=1
terraform apply -parallelism=1
```

Під час clone source CT 9001 отримує `lock: disk`; паралельні clones з єдиного
9001 небезпечні.

Звичайна робота після convergence:

```powershell
terraform plan -parallelism=5
terraform apply -parallelism=5
```

Якщо plan містить кілька LXC create/replace, потрібно використовувати
parallelism 1.

## Перевірка

```powershell
terraform fmt -check -recursive
terraform validate
terraform test
pwsh -NoProfile -File tests/lxc_placement.tests.ps1
```

Поточний результат: 5 Terraform tests passed, 0 failed; 7 offline placement
tests passed. Майбутні роботи: [BACKLOG.md](BACKLOG.md). Ліцензія:
[Apache 2.0](LICENSE).
