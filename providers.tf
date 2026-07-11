terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      # version = "0.111.0" # Можно зафиксировать версию после успешного init
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

provider "proxmox" {
  endpoint = var.pmx_api_url
  username = var.pmx_username
  password = var.pmx_password
  insecure = true

  # SSH блок закомментирован, так как его настройка и деплой ключей вынесены в отдельный пайплайн
  # ssh {
  #   username    = "root"
  #   private_key = file("C:/Users/Benden/.ssh/benden-syslab-keys/id_ed25519_root")
  # }
}