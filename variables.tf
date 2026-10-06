variable "pmx_api_url" {
  type        = string
  description = "Proxmox API endpoint, for example https://192.0.2.11:8006/api2/json"
}

variable "pmx_api_token" {
  type        = string
  default     = null
  sensitive   = true
  description = "Optional Proxmox API token"
}

variable "pmx_username" {
  type        = string
  default     = null
  description = "Optional Proxmox username for password authentication"
}

variable "pmx_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "Optional Proxmox password"
}

variable "dns_servers" {
  type        = list(string)
  default     = ["198.51.100.1", "1.1.1.1"]
  description = "DNS servers supplied through LXC initialization and VM Cloud-Init"
}

variable "bootstrap_ssh_key_path" {
  type        = string
  default     = "C:/example/keys/proxmox_ed25519"
  description = "Private-key file path used only for root SSH to Proxmox nodes by the LXC placement helper; never a key body"
}

variable "allow_lxc_shutdown" {
  type        = bool
  default     = false
  description = "Maintenance opt-in for graceful shutdown of a running LXC that requires safe rootfs placement correction"
}
