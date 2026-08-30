variable "pmx_api_url" {
  type        = string
  description = "https://192.168.1.210:8006/api2/json"
}

variable "pmx_api_token" {
  type        = string
  default     = null
  sensitive   = true
  description = "Токен доступа root@pam!terraform=... (если используется API-токен)"
}

variable "pmx_username" {
  type        = string
  default     = null
  description = "Имя пользователя Proxmox VE (например, root@pam), если используется парольная аутентификация"
}

variable "pmx_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "Пароль пользователя Proxmox VE, если используется парольная аутентификация"
}

variable "gateway_ip" {
  type        = string
  default     = "192.168.1.1"
  description = "IP-адрес шлюза по умолчанию для сетевых настроек виртуальных машин"
}

variable "vlan_id" {
  type        = number
  default     = 0
  description = "ID VLAN по умолчанию (0 - без тегирования)"
}

variable "dns_servers" {
  type        = list(string)
  default     = ["192.168.1.1", "8.8.8.8"]
  description = "Твой Кинетик + бэкап Гугла"
}

variable "ssd_storage" {
  type        = string
  default     = "storage-work"
  description = "Хранилище под базы данных, Vault и рабочие данные"
}

variable "cloudinit_datastore" {
  type        = string
  default     = "local"
  description = "Хранилище в Proxmox под образы Cloud-init"
}

variable "ssh_public_key" {
  type        = string
  description = "Публичный SSH ключ для административного доступа в контейнеры/ВМ"
}

variable "ssh_private_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Приватный SSH-ключ для беспарольного доступа (используется baseline провиженером)"
}

variable "proxmox_ssh_host" {
  type        = string
  default     = ""
  description = "IP/Hostname ноды Proxmox для подключения"
}

variable "proxmox_ssh_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Пароль Proxmox хоста"
}

variable "proxmox_ssh_private_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Приватный SSH-ключ Proxmox хоста"
}

variable "baseline_version" {
  type        = string
  default     = "1.0"
  description = "Версия базового слоя совместимости"
}

variable "bootstrap_transport" {
  type        = string
  default     = "pct"
  description = "Способ доставки baseline: pct или ssh"
}

variable "proxmox_nodes" {
  type = map(string)
  default = {
    "horus-pmx-node01" = "192.168.1.210"
    "horus-pmx-node02" = "192.168.1.220"
    "horus-pmx-node03" = "192.168.1.230"
    "horus-pmx-node04" = "192.168.1.240"
  }
  description = "Карта соответствия имен нод Proxmox их IP-адресам"
}
