variable "pmx_api_url" {
  type        = string
  description = "https://192.168.1.211:8006/api2/json"
}

variable "pmx_username" {
  type        = string
  default     = null
  description = "Имя пользователя для авторизации в Proxmox (например, root@pam)"
}

variable "pmx_password" {
  type        = string
  sensitive   = true
  default     = null
  description = "Пароль пользователя Proxmox"
}

variable "ssh_public_key" {
  type        = string
  description = "Публичный SSH ключ для административного доступа в контейнеры/ВМ"
}

variable "gateway_ip" {
  type        = string
  default     = "192.168.1.1"
  description = "IP-адрес шлюза по умолчанию для сетевых настроек виртуальных машин"
}

variable "dns_servers" {
  type    = list(string)
  default = ["192.168.1.1", "8.8.8.8"]
  description = "Твой Кинетик + бэкап Гугла"  
}

variable "ssd_storage" {
  type        = string
  default     = "data-ai"
  description = "Имя SSD-хранилища в Proxmox (например, data-ai или local-lvm) для размещения WAL и быстрых данных"
}