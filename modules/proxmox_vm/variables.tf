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
variable "ip_address"  { type = string }
variable "gateway"     { type = string }

variable "clone_template_id" {
  type    = number
  default = 9000
}

variable "ssh_public_key" { type = string }

variable "factory_node" {
  type        = string
  default     = "horus-pmx-node03"
  description = "Единственная родильная нода (Factory Node) для клонирования базовых VM cloud-images"
}

variable "additional_disks" {
  type = list(object({
    datastore  = string
    interface  = string
    size       = string
    mount_type = string
  }))
  default     = []
  description = "Дополнительные диски для постоянных данных ВМ"
}

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