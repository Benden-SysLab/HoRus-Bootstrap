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

# Ресурсы и ограничения
variable "cpu_units" {
  type    = number
  default = 1024
}

variable "cpu_limit" {
  type    = number
  default = 0
}

variable "swap" {
  type    = number
  default = 512
}

variable "rootfs_disk" {
  type = object({
    datastore_id = optional(string, "local")
    size         = optional(string, "8")
  })
  default = {}
  description = "Настройки корневого диска"
}

variable "vlan_id"     { type = number }
variable "ip_address"  { type = string } # В формате 192.168.X.Y/24
variable "gateway"     { type = string }

variable "ostemplate" {
  type    = string
  default = "infra:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
}

variable "ssh_public_key" { type = string }

variable "additional_mounts" {
  type = list(object({
    datastore = string  # Имя хранилища в Proxmox (например, "media")
    mp        = string  # Точка монтирования внутри контейнера (например, "/mnt/storage")
    size      = string  # Размер (например, "500G")
  }))
  default = []
}

variable "dns_servers" {
  type        = list(string)
  default     = ["192.168.1.1", "8.8.8.8"]
}

variable "root_password" {
  type        = string
  sensitive   = true
}

variable "mac_address" {
  type        = string
  default     = null
}

# Функционал контейнера
variable "container_features" {
  type = object({
    nesting = optional(bool, false)
    keyctl  = optional(bool, false)
    fuse    = optional(bool, false)
    mount   = optional(list(string), [])
    mknod   = optional(bool, false)
  })
  default     = {}
  description = "Дополнительные фичи (nesting, keyctl, fuse, и т.д.)"
}

variable "unprivileged" {
  type    = bool
  default = true
  description = "Является ли контейнер безпривилегированным"
}

variable "startup" {
  type = object({
    order    = optional(number, 30)
    up_delay = optional(number, 15)
    down_delay = optional(number, 15)
  })
  default = {}
}

variable "tags" {
  type    = list(string)
  default = []
}

variable "protection" {
  type    = bool
  default = false
}
