variable "target_node" { type = string }
variable "vmid"        { type = number }
variable "hostname"    { type = string }

variable "cores" {
  type    = number
  default = 1
}

variable "memory" {
  type    = number
  default = 512
}

variable "disk_size" {
  type    = string
  default = 8
}

variable "root_storage" {
  type        = string
  default     = "local-lvm"
  description = "Target datastore ID for the root filesystem"
}

variable "bridge" {
  type        = string
  default     = "vmbr0"
  description = "Network bridge interface"
}

variable "vlan_id"     { type = number }
variable "ip_address"  { type = string } # В формате 192.168.X.Y/24
variable "gateway"     { type = string }

variable "ostemplate" {
  type        = string
  default     = "storage-infra:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
  description = "Path/ID to LXC template file"

  validation {
    condition     = can(regex("^.*:vztmpl/.*\\.tar\\.(zst|gz|xz)$", var.ostemplate))
    error_message = "LXC ostemplate must be a valid Proxmox LXC template tarball (e.g. storage-infra:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst) and NOT a VM template."
  }
}

variable "ssh_public_key" { type = string }

variable "additional_mounts" {
  type = list(object({
    mount_type   = string           # "bind_mount" или "dedicated_volume"
    volume       = string           # Абсолютный путь хоста (например, "/mnt/pve/storage-media") или Proxmox storage ID (например, "storage-work")
    mp           = string           # Точка монтирования внутри контейнера (например, "/storage/media")
    size         = optional(string) # Размер диска для dedicated_volume (или null для bind_mount)
    storage_name = optional(string) # Имя хранилища в Proxmox для валидации топологии
  }))
  default     = []
  description = "Список точек монтирования для LXC контейнера"
}

variable "dns_servers" {
  type        = list(string)
  description = "List of DNS servers for the LXC container"
  default     = ["192.168.1.1", "8.8.8.8"]
}

variable "root_password" {
  type        = string
  sensitive   = true
  description = "Пароль суперпользователя root для LXC"
}

variable "feature_profile" {
  type        = string
  default     = "standard"
  description = "Профиль возможностей контейнера (standard, docker, system, storage)"
}

variable "bootstrap_transport" {
  type        = string
  default     = "none"
  description = "Способ доставки bootstrap скрипта: none, ssh, pct"
}

variable "baseline_version" {
  type        = string
  default     = "1.0.0"
  description = "Версия конфигурационного baseline для Debian 13 LXC"
}

variable "timezone" {
  type        = string
  default     = "Europe/Moscow"
  description = "Часовой пояс системы"
}

variable "ssh_private_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Приватный SSH ключ для аутентификации"
}

variable "proxmox_ssh_host" {
  type        = string
  default     = ""
  description = "IP/Hostname ноды Proxmox для pct push"
}

variable "proxmox_ssh_private_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Приватный SSH ключ Proxmox хоста"
}

variable "proxmox_ssh_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Пароль Proxmox хоста"
}