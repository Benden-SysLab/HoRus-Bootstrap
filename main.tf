# ==============================================================================
# ЛОКАЛЬНОЕ ХРАНЕНИЕ СЕКРЕТОВ (Исключено из репозитория через .gitignore)
# ==============================================================================

locals {
  # Считываем root-пароль из локального файла root_password.txt, который добавлен в .gitignore.
  # Функция trimspace удаляет случайные переводы строк или пробелы.
  root_password = trimspace(file("${path.module}/root_password.txt"))
}

# ==============================================================================
# HOST: horus-pmx-srv01 (Вычисления, Тяжелый деплой, GPU + HDD)
# ==============================================================================

# Jenkins Master (ВМ, Шаблон 9000)
module "horus-jnk-srv01" {
  source           = "./modules/proxmox_vm"
  target_node      = "horus-pmx-srv01"
  vmid             = 101
  hostname         = "horus-jnk-srv01"
  cores            = 2
  memory           = 4096
  vlan_id          = 0
  ip_address       = "192.168.1.212/24"
  gateway          = var.gateway_ip
  dns_servers      = var.dns_servers
  ssh_public_key   = var.ssh_public_key
  root_password    = local.root_password
  disk_file_format = "qcow2"
}

# ИИ-бэкенд Сеть/Деплой (LXC)
module "horus-ai-srv01" {
  source         = "./modules/proxmox_lxc"
  target_node    = "horus-pmx-srv01"
  vmid           = 102
  hostname       = "horus-ai-srv01"
  cores          = 4
  memory         = 4096
  rootfs_disk    = { size = "32" }
  vlan_id        = 0
  ip_address     = "192.168.1.213/24"
  gateway        = var.gateway_ip
  dns_servers    = var.dns_servers
  ssh_public_key = var.ssh_public_key
  root_password  = local.root_password
}

# ИИ-бэкенд Камеры/Зрение (LXC)
module "horus-ai-srv02" {
  source         = "./modules/proxmox_lxc"
  target_node    = "horus-pmx-srv01"
  vmid           = 103
  hostname       = "horus-ai-srv02"
  cores          = 4
  memory         = 4096
  rootfs_disk    = { size = "32" }
  vlan_id        = 0
  ip_address     = "192.168.1.214/24"
  gateway        = var.gateway_ip
  dns_servers    = var.dns_servers
  ssh_public_key = var.ssh_public_key
  root_password  = local.root_password

  # Подключаем хранилище для архивов камер
  additional_mounts = [
    {
      datastore = "cameras"
      mp        = "/storage/cameras"
      size      = "420G"
    }
  ]
}

# CasaOS (LXC)
module "horus-media-srv01" {
  source         = "./modules/proxmox_lxc"
  target_node    = "horus-pmx-srv01"
  vmid           = 104
  hostname       = "horus-media-srv01"
  cores          = 2
  memory         = 2048
  rootfs_disk    = { size = "16" }
  vlan_id        = 0
  ip_address     = "192.168.1.215/24"
  gateway        = var.gateway_ip
  dns_servers    = var.dns_servers
  ssh_public_key = var.ssh_public_key
  root_password  = local.root_password

  # Прокидываем диск под основную медиатеку CasaOS
  additional_mounts = [
    {
      datastore = "storage"
      mp        = "/storage"
      size      = "1740G"
    }
  ]
}

# JoyFilm (LXC)
module "horus-media-srv02" {
  source         = "./modules/proxmox_lxc"
  target_node    = "horus-pmx-srv01"
  vmid           = 105
  hostname       = "horus-media-srv02"
  cores          = 4
  memory         = 4096
  rootfs_disk    = { size = "32" }
  vlan_id        = 0
  ip_address     = "192.168.1.216/24"
  gateway        = var.gateway_ip
  dns_servers    = var.dns_servers
  ssh_public_key = var.ssh_public_key
  root_password  = local.root_password

  # Прокидываем раздачу или торрент-хранилище
  additional_mounts = [
    {
      datastore = "media"
      mp        = "/storage/media"
      size      = "2662G"
    }
  ]
}

# Билд-агент Jenkins (LXC)
module "horus-agent-srv01" {
  source         = "./modules/proxmox_lxc"
  target_node    = "horus-pmx-srv01"
  vmid           = 106
  hostname       = "horus-agent-srv01"
  cores          = 4
  memory         = 4096
  rootfs_disk    = { size = "40" }
  vlan_id        = 0
  ip_address     = "192.168.1.217/24"
  gateway        = var.gateway_ip
  dns_servers    = var.dns_servers
  ssh_public_key = var.ssh_public_key
  root_password  = local.root_password
}

# Локальный защитник кода GitGuardian/TruffleHog/Trivy (LXC)
module "horus-gg-srv01" {
  source         = "./modules/proxmox_lxc"
  target_node    = "horus-pmx-srv01"
  vmid           = 107
  hostname       = "horus-gg-srv01"
  cores          = 2
  memory         = 2048
  rootfs_disk    = { size = "20" }
  vlan_id        = 0
  ip_address     = "192.168.1.218/24"
  gateway        = var.gateway_ip
  dns_servers    = var.dns_servers
  ssh_public_key = var.ssh_public_key
  root_password  = local.root_password
}


# ==============================================================================
# HOST: horus-pmx-srv02 (Инфраструктурное ядро, IAM, Данные на SSD)
# ==============================================================================

# Authentik IAM (LXC)
module "horus-iam-srv01" {
  source         = "./modules/proxmox_lxc"
  target_node    = "horus-pmx-srv02"
  vmid           = 201
  hostname       = "horus-iam-srv01"
  cores          = 2
  memory         = 2048
  rootfs_disk    = { size = "20" }
  vlan_id        = 0
  ip_address     = "192.168.1.222/24"
  gateway        = var.gateway_ip
  dns_servers    = var.dns_servers
  ssh_public_key = var.ssh_public_key
  root_password  = local.root_password
}

# Gitea (LXC)
module "horus-git-srv01" {
  source         = "./modules/proxmox_lxc"
  target_node    = "horus-pmx-srv02"
  vmid           = 202
  hostname       = "horus-git-srv01"
  cores          = 2
  memory         = 2048
  rootfs_disk    = { size = "20" }
  vlan_id        = 0
  ip_address     = "192.168.1.223/24"
  gateway        = var.gateway_ip
  dns_servers    = var.dns_servers
  ssh_public_key = var.ssh_public_key
  root_password  = local.root_password
}

# HashiCorp Vault (ВМ, Шаблон 9000)
module "horus-vlt-srv01" {
  source           = "./modules/proxmox_vm"
  target_node      = "horus-pmx-srv02"
  vmid             = 203
  hostname         = "horus-vlt-srv01"
  cores            = 2
  memory           = 2048
  vlan_id          = 0
  ip_address       = "192.168.1.224/24"
  gateway          = var.gateway_ip
  dns_servers      = var.dns_servers
  ssh_public_key   = var.ssh_public_key
  root_password    = local.root_password
  disk_file_format = "qcow2"
}

# Wiki.js (LXC)
module "horus-wiki-srv01" {
  source         = "./modules/proxmox_lxc"
  target_node    = "horus-pmx-srv02"
  vmid           = 204
  hostname       = "horus-wiki-srv01"
  cores          = 1
  memory         = 1024
  rootfs_disk    = { size = "15" }
  vlan_id        = 0
  ip_address     = "192.168.1.225/24"
  gateway        = var.gateway_ip
  dns_servers    = var.dns_servers
  ssh_public_key = var.ssh_public_key
  root_password  = local.root_password
}

# PostgreSQL Cluster (LXC)
module "horus-db-srv01" {
  source         = "./modules/proxmox_lxc"
  target_node    = "horus-pmx-srv02"
  vmid           = 205
  hostname       = "horus-db-srv01"
  cores          = 2
  memory         = 4096
  rootfs_disk    = { size = "30" }
  vlan_id        = 0
  ip_address     = "192.168.1.226/24"
  gateway        = var.gateway_ip
  dns_servers    = var.dns_servers
  ssh_public_key = var.ssh_public_key
  root_password  = local.root_password
  container_features = { nesting = true }

  # Мапим выделенные датасторы под базу данных (вложенные точки монтирования)
  additional_mounts = [
    {
      datastore = "data-pg"
      mp        = "/var/lib/postgresql/data"
      size      = "860G"
    },
    {
      datastore = "data-ai"
      mp        = "/var/lib/postgresql/wal_ssd"
      size      = "10G"
    }
  ]
}

# Harbor Registry (LXC)
module "horus-reg-srv01" {
  source         = "./modules/proxmox_lxc"
  target_node    = "horus-pmx-srv02"
  vmid           = 206
  hostname       = "horus-reg-srv01"
  cores          = 2
  memory         = 4096
  rootfs_disk    = { size = "40" }
  vlan_id        = 0
  ip_address     = "192.168.1.227/24"
  gateway        = var.gateway_ip
  dns_servers    = var.dns_servers
  ssh_public_key = var.ssh_public_key
  root_password  = local.root_password
  container_features = { nesting = true }
}

# Automation Node Ansible (LXC)
module "horus-ans-srv01" {
  source         = "./modules/proxmox_lxc"
  target_node    = "horus-pmx-srv02"
  vmid           = 207
  hostname       = "horus-ans-srv01"
  cores          = 2
  memory         = 4096
  rootfs_disk    = { size = "30" }
  vlan_id        = 0
  ip_address     = "192.168.1.228/24"
  gateway        = var.gateway_ip
  dns_servers    = var.dns_servers
  ssh_public_key = var.ssh_public_key
  root_password  = local.root_password
}

# Тяжелый ИИ (Мимир) (LXC)
module "horus-ai-srv03" {
  source         = "./modules/proxmox_lxc"
  target_node    = "horus-pmx-srv02"
  vmid           = 208
  hostname       = "horus-ai-srv03"
  cores          = 4
  memory         = 8192
  rootfs_disk    = { size = "32" }
  vlan_id        = 0
  ip_address     = "192.168.1.229/24"
  gateway        = var.gateway_ip
  dns_servers    = var.dns_servers
  ssh_public_key = var.ssh_public_key
  root_password  = local.root_password

  # Подключаем выделенный 480GB SSD под веса моделей и данные
  additional_mounts = [
    {
      datastore = "data-ai"
      mp        = "/data-ai"
      size      = "410G"
    }
  ]
}


# ==============================================================================
# HOST: horus-pmx-srv03 (Микросервисный стек наблюдаемости и S3)
# ==============================================================================

# Grafana (LXC)
module "horus-grf-srv01" {
  source         = "./modules/proxmox_lxc"
  target_node    = "horus-pmx-srv03"
  vmid           = 301
  hostname       = "horus-grf-srv01"
  cores          = 1
  memory         = 1024
  rootfs_disk    = { size = "10" }
  vlan_id        = 0
  ip_address     = "192.168.1.232/24"
  gateway        = var.gateway_ip
  dns_servers    = var.dns_servers
  ssh_public_key = var.ssh_public_key
  root_password  = local.root_password
}

# Prometheus (LXC)
module "horus-pm-srv01" {
  source         = "./modules/proxmox_lxc"
  target_node    = "horus-pmx-srv03"
  vmid           = 302
  hostname       = "horus-pm-srv01"
  cores          = 2
  memory         = 2048
  rootfs_disk    = { size = "15" }
  vlan_id        = 0
  ip_address     = "192.168.1.233/24"
  gateway        = var.gateway_ip
  dns_servers    = var.dns_servers
  ssh_public_key = var.ssh_public_key
  root_password  = local.root_password
}

# Loki (LXC)
module "horus-lok-srv01" {
  source         = "./modules/proxmox_lxc"
  target_node    = "horus-pmx-srv03"
  vmid           = 303
  hostname       = "horus-lok-srv01"
  cores          = 2
  memory         = 2048
  rootfs_disk    = { size = "15" }
  vlan_id        = 0
  ip_address     = "192.168.1.234/24"
  gateway        = var.gateway_ip
  dns_servers    = var.dns_servers
  ssh_public_key = var.ssh_public_key
  root_password  = local.root_password
}

# OpenTelemetry Collector (LXC)
module "horus-otel-srv01" {
  source         = "./modules/proxmox_lxc"
  target_node    = "horus-pmx-srv03"
  vmid           = 304
  hostname       = "horus-otel-srv01"
  cores          = 1
  memory         = 1024
  rootfs_disk    = { size = "5" }
  vlan_id        = 0
  ip_address     = "192.168.1.235/24"
  gateway        = var.gateway_ip
  dns_servers    = var.dns_servers
  ssh_public_key = var.ssh_public_key
  root_password  = local.root_password
}

# MinIO S3 Storage (LXC)
module "horus-s3-srv01" {
  source         = "./modules/proxmox_lxc"
  target_node    = "horus-pmx-srv03"
  vmid           = 305
  hostname       = "horus-s3-srv01"
  cores          = 2
  memory         = 2048
  rootfs_disk    = { size = "40" }
  vlan_id        = 0
  ip_address     = "192.168.1.236/24"
  gateway        = var.gateway_ip
  dns_servers    = var.dns_servers
  ssh_public_key = var.ssh_public_key
  root_password  = local.root_password

  # Отдаем под бакеты MinIO весь HDD-диск третьей ноды
  additional_mounts = [
    {
      datastore = "data"
      mp        = "/data"
      size      = "430G"
    }
  ]
}

# AI Operations Engine (LXC)
module "horus-ai-srv04" {
  source         = "./modules/proxmox_lxc"
  target_node    = "horus-pmx-srv03"
  vmid           = 306
  hostname       = "horus-ai-srv04"
  cores          = 4
  memory         = 4096
  rootfs_disk    = { size = "32" }
  vlan_id        = 0
  ip_address     = "192.168.1.237/24"
  gateway        = var.gateway_ip
  dns_servers    = var.dns_servers
  ssh_public_key = var.ssh_public_key
  root_password  = local.root_password
}
