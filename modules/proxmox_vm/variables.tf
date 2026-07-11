variable "target_node" { type = string }
variable "vmid"        { type = number }
variable "hostname"    { type = string }

variable "cores" {
  type    = number
  default = 2
}

variable "memory" {
  type    = number
  default = 2048
}

variable "disk_size" {
  type    = string
  default = "32"
}

variable "vlan_id"     { type = number }
variable "ip_address"  { type = string }
variable "gateway"     { type = string }

variable "clone_template_id" {
  type    = number
  default = 9000
}

variable "ssh_public_key" { type = string }

variable "dns_servers" {
  type        = list(string)
  description = "List of DNS servers for the VM"
  default     = ["192.168.1.1", "8.8.8.8"]
}

variable "root_password" {
  type        = string
  sensitive   = true
  description = "Пароль суперпользователя root для ВМ"
}

variable "mac_address" {
  type        = string
  description = "Фиксированный MAC-адрес ВМ. Если не задан, вычисляется автоматически на основе VMID."
  default     = null
}

variable "disk_file_format" {
  type        = string
  default     = "raw"
  description = "Формат файла диска ВМ (например, raw или qcow2)"
}