variable "target_node" { type = string }
variable "vmid" { type = number }
variable "hostname" { type = string }
variable "cores" { type = number }
variable "memory" { type = number }

variable "disk_size" {
  type = string
  validation {
    condition     = try(tonumber(var.disk_size) >= 8, false)
    error_message = "Golden LXC 9001 has an 8 GiB rootfs; LXC rootfs cannot be smaller."
  }
}

variable "root_storage" { type = string }
variable "bridge" { type = string }
variable "vlan_id" { type = number }
variable "ip_address" { type = string }
variable "gateway" { type = string }
variable "dns_servers" { type = list(string) }
variable "feature_profile" { type = string }

variable "clone_template_id" {
  type    = number
  default = 9001
}

variable "clone_node" {
  type    = string
  default = "horus-pmx-node03"
}

variable "clone_storage" {
  type    = string
  default = "storage-infra"
}

variable "private_mounts" {
  type = list(object({
    datastore_id = string
    path         = string
    size         = string
  }))
  default = []
  validation {
    condition     = alltrue([for mount in var.private_mounts : mount.size == "0" && startswith(mount.path, "/")])
    error_message = "Private state must use Proxmox-managed size=0 directory volumes and absolute guest paths."
  }
}

variable "bootstrap_ssh_key_path" {
  type        = string
  description = "OpenSSH private-key file path for root access to Proxmox nodes"
}

variable "allow_lxc_shutdown" {
  type        = bool
  default     = false
  description = "Allow graceful shutdown when a running LXC requires safe rootfs placement correction"
}
