locals {
  ssh_identity_spec = {
    vmid                     = var.vmid
    hostname                 = var.hostname
    template_vmid            = var.clone_template_id
    target_node              = var.target_node
    template_host_key_sha256 = var.clone_template_host_key_sha256
  }
  ssh_identity_script   = abspath("${path.module}/../../scripts/lxc_ssh_identity.ps1")
  ssh_identity_library  = abspath("${path.module}/../../scripts/lib/Horus.LxcSshIdentity.ps1")
  ssh_identity_revision = [filesha256(local.ssh_identity_script), filesha256(local.ssh_identity_library)]
}

# Every provider clone passes this barrier before placement/start. New stopped
# clones always receive fresh SSH host keys. Existing running LXC workloads are
# changed only when their ED25519 key is missing or exactly matches Golden 9001.
resource "terraform_data" "ssh_identity" {
  depends_on = [proxmox_virtual_environment_container.lxc_node]

  input = local.ssh_identity_spec
  triggers_replace = [
    local.ssh_identity_spec,
    local.ssh_identity_revision,
  ]

  lifecycle {
    replace_triggered_by = [proxmox_virtual_environment_container.lxc_node]
  }

  provisioner "local-exec" {
    interpreter = ["pwsh", "-NoLogo", "-NoProfile", "-NonInteractive", "-Command"]
    command     = "& $env:HORUS_SCRIPT_PATH"
    environment = {
      HORUS_SCRIPT_PATH  = local.ssh_identity_script
      HORUS_SPEC_JSON    = jsonencode(self.input)
      HORUS_SSH_KEY_PATH = var.bootstrap_ssh_key_path
    }
  }
}
