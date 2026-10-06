variable "pmx_api_url" {
  type        = string
  description = "Proxmox API endpoint, for example https://192.0.2.10:8006/api2/json"
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

variable "environment" {
  description = "Environment-specific network, address and storage coordinates. Keep real values in ignored terraform.tfvars."
  nullable    = false

  type = object({
    management = object({
      cidr    = string
      gateway = string
      nodes   = map(string)
    })
    vlan_networks = map(object({
      cidr    = string
      gateway = string
    }))
    workload_ips  = map(string)
    dns_servers   = list(string)
    storage_paths = map(string)
    guest_paths   = map(string)
    nfs = map(object({
      server = string
      export = string
    }))
  })

  validation {
    condition = alltrue([
      length(setsubtract(toset(["horus-pmx-node01", "horus-pmx-node02", "horus-pmx-node03", "horus-pmx-node04"]), toset(keys(var.environment.management.nodes)))) == 0,
      length(setsubtract(toset(["101", "110", "120", "130", "140", "150", "160", "170", "180"]), toset(keys(var.environment.vlan_networks)))) == 0,
      length(setsubtract(toset([
        "horus-lb-srv01", "horus-agent-srv01", "horus-jnk-srv01", "horus-ai-srv01", "horus-db-srv01", "horus-media-srv01", "horus-k8sw-srv01",
        "horus-ans-srv01", "horus-ai-srv02", "horus-db-srv02", "horus-vec-srv01", "horus-cache-srv01", "horus-iam-srv01", "horus-media-srv02", "horus-k8sw-srv02", "horus-k8sc-srv01",
        "horus-db-srv03", "horus-vlt-srv01", "horus-wiki-srv01", "horus-git-srv01", "horus-work-srv01", "horus-reg-srv01",
        "horus-grf-srv01", "horus-pm-srv01", "horus-lok-srv01", "horus-otel-srv01", "horus-s3-srv01", "horus-ai-srv03"
      ]), toset(keys(var.environment.workload_ips)))) == 0,
      length(setsubtract(toset(["guardian-data", "mimir-data", "infra", "artifacts", "logs", "media"]), toset(keys(var.environment.storage_paths)))) == 0,
      length(setsubtract(toset(["artifacts-shared", "guardian-data", "media", "mimir-data", "mimir-postgres", "mimir-vectors", "infra-postgres", "infra-wiki", "infra-gitea", "artifacts-registry", "logs"]), toset(keys(var.environment.guest_paths)))) == 0,
      length(setsubtract(toset(["media", "artifacts"]), toset(keys(var.environment.nfs)))) == 0
    ])
    error_message = "environment must define every required management node, VLAN, workload IP, storage path, guest path and NFS endpoint. Extra entries are allowed."
  }

  validation {
    condition = alltrue(concat(
      [can(cidrhost(var.environment.management.cidr, 0)), can(cidrhost("${var.environment.management.gateway}/32", 0))],
      [for value in values(var.environment.management.nodes) : can(cidrhost("${value}/32", 0))],
      flatten([for network in values(var.environment.vlan_networks) : [can(cidrhost(network.cidr, 0)), can(cidrhost("${network.gateway}/32", 0))]]),
      [for value in values(var.environment.workload_ips) : can(cidrhost(value, 0))],
      [for value in var.environment.dns_servers : can(cidrhost("${value}/32", 0))],
      [for value in values(var.environment.storage_paths) : startswith(value, "/")],
      [for value in values(var.environment.guest_paths) : startswith(value, "/")],
      flatten([for endpoint in values(var.environment.nfs) : [can(cidrhost("${endpoint.server}/32", 0)), startswith(endpoint.export, "/")]])
    ))
    error_message = "environment contains an invalid IP/CIDR or a non-absolute storage, guest or NFS path."
  }
}

variable "bootstrap_ssh_key_path" {
  type        = string
  description = "Private-key file path used only for root SSH to Proxmox nodes by the LXC placement helper; never a key body"
}

variable "allow_lxc_shutdown" {
  type        = bool
  default     = false
  description = "Maintenance opt-in for graceful shutdown of a running LXC that requires safe rootfs placement correction"
}
