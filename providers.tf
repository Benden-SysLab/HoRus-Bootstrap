terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.115.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.pmx_api_url
  api_token = var.pmx_api_token
  username  = var.pmx_username
  password  = var.pmx_password
  insecure  = true
}
