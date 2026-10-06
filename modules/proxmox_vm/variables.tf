variable "target_node" { type = string }
variable "factory_node" { type = string }
variable "vmid" { type = number }
variable "hostname" { type = string }
variable "cores" { type = number }
variable "memory" { type = number }

variable "disk_size" {
  type = string
  validation {
    condition     = try(tonumber(var.disk_size) >= 12, false)
    error_message = "Golden VM 9000 has a 12 GiB root disk; VM root disks cannot be smaller."
  }
}

variable "root_storage" { type = string }
variable "bridge" { type = string }
variable "vlan_id" { type = number }
variable "ip_address" { type = string }
variable "gateway" { type = string }
variable "dns_servers" { type = list(string) }

variable "clone_template_id" {
  type    = number
  default = 9000
}
