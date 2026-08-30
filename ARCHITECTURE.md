# Архитектурный паспорт домашнего кластера "HoRus" (4-Node Topography v1.0)
**Дата актуализации:** 29 августа 2026 г.  
**Целевая платформа:** Proxmox VE 9.2.x (4 ноды: node01..node04) + Физический шлюз Zotac (Bifrost)  
**Концепция:** Enterprise-grade микросервисный кластер с ИИ-ориентированным управлением (AIOps), родительской нодой генерации ВМ (Factory Node), централизованным NAS и SSO-авторизацией.

---

## 1. Детерминированный сетевой регламент и IP Addressing Policy
Каждая физическая нода имеет строго зафиксированный сетевой сегмент с порядковой нумерацией сервисов:

* **horus-pmx-node01** (`192.168.1.210`): Workloads `192.168.1.211` – `192.168.1.216` (6 workloads)
* **horus-pmx-node02** (`192.168.1.220`): Workloads `192.168.1.221` – `192.168.1.226` (6 workloads)
* **horus-pmx-node03** (`192.168.1.230`): Workloads `192.168.1.231` – `192.168.1.234` (4 workloads - Factory Node & NAS)
* **horus-pmx-node04** (`192.168.1.240`): Workloads `192.168.1.241` – `192.168.1.246` (6 workloads - Observability & S3)

### Подключение к сети:
* Стандартный мост Proxmox VE: `vmbr0`
* `vlan_id = 0` (текущий деплой-скоуп)

---

## 2. Factory Model & Image Lifecycle

### Хранилища и роли:
1. **`local-lvm` (целевые ноды):**
   - Root-диски (rootfs) ВСЕХ 22 виртуальных машин и LXC-контейнеров создаются на локальном LVM-thin хранилище целевой ноды.
2. **Factory Node (`horus-pmx-node03`):**
   - Содержит Golden VM Image 9000 (`debian-13-golden-template`) для полнофункционального клонирования ВМ.
   - Содержит LXC Template в `storage-infra`: `storage-infra:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst`.

### Жизненный цикл развертывания:
* **Debian LXC Контейнеры (20 шт):** Разворачиваются **напрямую** из LXC-шаблона `storage-infra:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst` на целевой ноде через `proxmox_virtual_environment_container` (без клонирования, промежуточных контейнеров или миграций).
* **Debian Виртуальные Машины (VM, 2 шт):** Клонируются через `full clone` из Golden VM Template 9000 на Factory Node (`node03`) и размещаются на целевой ноде (`horus-pmx-node01` для Jenkins Master и `horus-pmx-node03` для Vault).

---

## 3. Дисковая политика и классификация хранилищ (Storage Categories)

Инфраструктура хранилищ HoRus подразделяется на 6 семантических категорий:

1. **`local-lvm` (Root Disks):**
   - Локальные LVM-thin пулы на каждой из 4 нод (`node01`..`node04`).
   - Используются **исключительно** под корневые файловые системы (rootfs 32GB) всех 22 виртуальных машин и LXC-контейнеров.

2. **Dedicated Persistent Volumes (Выделенные тома данных):**
   - **`storage-work`** (NFS `node03`, 1 TB Seagate `/dev/sdc`):
     - Gitea (`horus-git-srv01`, 301): dedicated volume 100GB в `/var/lib/gitea`.
     - PostgreSQL (`horus-db-srv01`, 304): dedicated volume 800GB в `/var/lib/postgresql/data`.
     - Vault (`horus-vlt-srv01`, 302): дополнительный KVM-диск `scsi1` 50GB.

3. **Existing NFS Bind Mounts (Существующие файловые системы NFS):**
   - **`storage-media`** (NFS `node03`, 3 TB Seagate `/dev/sdb`):
     - Bind mount `/mnt/pve/storage-media` без создания новыx volumes.
     - Потребители: LXC 104 (`/storage/media`) и LXC 202 (`/storage/media`).
   - **`storage`** (NFS `node03`, 2 TB WD Red `/dev/sda`):
     - Bind mount `/mnt/pve/storage` без создания нового volume.
     - Потребитель: LXC 202 CasaOS (`/storage/files`).

4. **Local AI Storage (Локальное ИИ-хранилище):**
   - **`storage-ai`** (`node02` local dir, 480 GB SSD):
     - Выделенный том 400GB в `/data-ai` для ИИ-модели Mimir (`horus-ai-srv03`, 205). Доступен только на `node02`.

5. **Local Monitoring & S3 Storage (Локальное хранилище логов):**
   - **`storage-logs`** (`node04` local dir, 500 GB HDD `/dev/sdb`):
     - Выделенный том 430GB в `/data` для MinIO S3 backend (`horus-s3-srv01`, 405). Доступен только на `node04`.

6. **Factory Artifacts (Инфраструктурные артефакты фабрики):**
   - **`storage-infra`** (NFS `node03`, 1 TB Toshiba `/dev/sdd`):
     - Хранение ISO-образов, LXC-шаблонов (`debian-13-standard_13.6-1_amd64.tar.zst`), артефактов VM 9000, бэкапов и сниппетов.

---

| Имя Storage | Категория | Физический владелец | Тип | Емкость / Диск | Разрешенные потребители | Назначение |
| :--- | :--- | :--- | :---: | :--- | :--- | :--- |
| **`local-lvm`** | Root Disks | Per-node (`node01`..`node04`) | LVM-thin | System SSD | Все 4 ноды | Rootfs (32GB) для всех 22 workloads |
| **`storage`** | Existing NFS | `node03` | NFS | 2 TB (WD Red `/dev/sda`) | `node01`..`node04` | NAS, CasaOS (`bind_mount` `/mnt/pve/storage`) |
| **`storage-media`**| Existing NFS | `node03` | NFS | 3 TB (Seagate `/dev/sdb`) | **`node01`, `node02` ONLY** | Медиатека (`bind_mount` `/mnt/pve/storage-media`) |
| **`storage-work`** | Dedicated Volume | `node03` | NFS | 1 TB (Seagate `/dev/sdc`) | `node01`..`node04` | Данные Postgres (800G), Vault (50G), Gitea (100G) |
| **`storage-infra`**| Factory Artifacts | `node03` | NFS | 1 TB (Toshiba `/dev/sdd`) | `node01`..`node04` | LXC шаблоны, ISO, VM артефакты, бэкапы |
| **`storage-ai`** | Local AI Storage | `node02` | Local Dir | 480 GB SSD | **`node02` ONLY** | Mimir AI weights (`horus-ai-srv03`, 400G) |
| **`storage-logs`** | Local Logs/S3 | `node04` | Local Dir | 500 GB HDD (`/dev/sdb`) | **`node04` ONLY** | MinIO S3 backend (`horus-s3-srv01`, 430G) |

---

## 4. Карта распределения физических узлов и 22 сервисов

### 🚀 Хост: horus-pmx-node01 (192.168.1.210 - Compute, GPU GTX 1660 Super)
*Физические ресурсы: 8 CPU / 31.04 GiB RAM. Выделено в IaC: 18 vCPU / 22 GB RAM*

| VMID | Имя узла | Тип | vCPU | RAM | IP Address | Root Storage | Persistent Mounts / Data |
| :---: | :--- | :---: | :---: | :---: | :--- | :--- | :--- |
| **101** | `horus-jnk-srv01` | **VM** | 2 | 4 GB | `192.168.1.211/24` | `local-lvm` | Golden VM 9000 (Jenkins Master) |
| **102** | `horus-ai-srv01` | **LXC** | 4 | 4 GB | `192.168.1.212/24` | `local-lvm` | AI Backend / Deploy |
| **103** | `horus-ai-srv02` | **LXC** | 4 | 4 GB | `192.168.1.213/24` | `local-lvm` | Computer Vision / Cameras |
| **104** | `horus-media-srv02` | **LXC** | 4 | 4 GB | `192.168.1.214/24` | `local-lvm` | `bind_mount` `/mnt/pve/storage-media` -> `/storage/media` |
| **105** | `horus-lb-srv01` | **LXC** | 2 | 2 GB | `192.168.1.215/24` | `local-lvm` | Nginx / Envoy / HAProxy Load Balancer |
| **106** | `horus-ans-srv01` | **LXC** | 2 | 4 GB | `192.168.1.216/24` | `local-lvm` | Ansible Automation Node |

---

### 🔒 Хост: horus-pmx-node02 (192.168.1.220 - Worker, GPU RTX 3060, Local SSD storage-ai)
*Физические ресурсы: 8 CPU / 31.04 GiB RAM. Выделено в IaC: 16 vCPU / 22 GB RAM*

| VMID | Имя узла | Тип | vCPU | RAM | IP Address | Root Storage | Persistent Mounts / Data |
| :---: | :--- | :---: | :---: | :---: | :--- | :--- | :--- |
| **201** | `horus-iam-srv01` | **LXC** | 2 | 2 GB | `192.168.1.221/24` | `local-lvm` | Authentik IAM / SSO |
| **202** | `horus-media-srv01` | **LXC** | 2 | 2 GB | `192.168.1.222/24` | `local-lvm` | `bind_mount` `/mnt/pve/storage` -> `/storage/files`, `/mnt/pve/storage-media` -> `/storage/media` |
| **203** | `horus-agent-srv01` | **LXC** | 4 | 4 GB | `192.168.1.223/24` | `local-lvm` | Jenkins Build Agent |
| **204** | `horus-gg-srv01` | **LXC** | 2 | 2 GB | `192.168.1.224/24` | `local-lvm` | GitGuardian / TruffleHog |
| **205** | `horus-ai-srv03` | **LXC** | 4 | 8 GB | `192.168.1.225/24` | `local-lvm` | `storage-ai` -> `/data-ai` (400G) |
| **206** | `horus-reg-srv01` | **LXC** | 2 | 4 GB | `192.168.1.226/24` | `local-lvm` | Harbor Container Registry |

---

### 🏭 Хост: horus-pmx-node03 (192.168.1.230 - Factory Node, Stateful, NAS, Databases)
*Физические ресурсы: 8 CPU / 15.58 GiB RAM. Выделено в IaC: 7 vCPU / 9 GB RAM*

| VMID | Имя узла | Тип | vCPU | RAM | IP Address | Root Storage | Persistent Mounts / Data |
| :---: | :--- | :---: | :---: | :---: | :--- | :--- | :--- |
| **301** | `horus-git-srv01` | **LXC** | 2 | 2 GB | `192.168.1.231/24` | `local-lvm` | `storage-work` -> `/var/lib/gitea` (100G) |
| **302** | `horus-vlt-srv01` | **VM** | 2 | 2 GB | `192.168.1.232/24` | `local-lvm` | Golden VM 9000 (HashiCorp Vault, `storage-work` scsi1 50G) |
| **303** | `horus-wiki-srv01` | **LXC** | 1 | 1 GB | `192.168.1.233/24` | `local-lvm` | Wiki.js Knowledge Base |
| **304** | `horus-db-srv01` | **LXC** | 2 | 4 GB | `192.168.1.234/24` | `local-lvm` | `storage-work` -> `/var/lib/postgresql/data` (800G) |

---

### 📊 Хост: horus-pmx-node04 (192.168.1.240 - Observability, S3, Local HDD storage-logs)
*Физические ресурсы: 4 CPU / 15.54 GiB RAM. Выделено в IaC: 12 vCPU / 12 GB RAM*

| VMID | Имя узла | Тип | vCPU | RAM | IP Address | Root Storage | Persistent Mounts / Data |
| :---: | :--- | :---: | :---: | :---: | :--- | :--- | :--- |
| **401** | `horus-grf-srv01` | **LXC** | 1 | 1 GB | `192.168.1.241/24` | `local-lvm` | Grafana Dashboards |
| **402** | `horus-pm-srv01` | **LXC** | 2 | 2 GB | `192.168.1.242/24` | `local-lvm` | Prometheus Metrics |
| **403** | `horus-lok-srv01` | **LXC** | 2 | 2 GB | `192.168.1.243/24` | `local-lvm` | Loki Log Aggregation |
| **404** | `horus-otel-srv01` | **LXC** | 1 | 1 GB | `192.168.1.244/24` | `local-lvm` | OpenTelemetry Collector |
| **405** | `horus-s3-srv01` | **LXC** | 2 | 2 GB | `192.168.1.245/24` | `local-lvm` | `storage-logs` -> `/data` (430G) |
| **406** | `horus-ai-srv04` | **LXC** | 4 | 4 GB | `192.168.1.246/24` | `local-lvm` | AIOps Root-Cause Analysis |

---

*Примечание: VMID 305 (`horus-retro-srv01` / Windows XP) отсутствует в текущем deployment scope и планируется как отдельный самостоятельный проект.*
