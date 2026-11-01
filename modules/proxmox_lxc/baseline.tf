locals {
  guest_baseline_spec = {
    vmid        = var.vmid
    hostname    = var.hostname
    target_node = var.target_node
    timezone    = var.timezone
  }
  guest_baseline_script   = abspath("${path.module}/../../scripts/lxc_guest_baseline.ps1")
  guest_baseline_library  = abspath("${path.module}/../../scripts/lib/Horus.LxcGuestBaseline.ps1")
  guest_baseline_revision = [filesha256(local.guest_baseline_script), filesha256(local.guest_baseline_library)]
}

# The provider does not expose the Proxmox LXC timezone field. This barrier
# completes the minimal guest baseline while the clone is still stopped:
# Europe/Moscow and the Jenkins/Ansible deployment sudo policy.
resource "terraform_data" "guest_baseline" {
  depends_on = [terraform_data.ssh_identity]

  input = local.guest_baseline_spec
  triggers_replace = [
    local.guest_baseline_spec,
    local.guest_baseline_revision,
  ]

  lifecycle {
    replace_triggered_by = [proxmox_virtual_environment_container.lxc_node]
  }

  provisioner "local-exec" {
    interpreter = ["pwsh", "-NoLogo", "-NoProfile", "-NonInteractive", "-Command"]
    command     = "& $env:HORUS_SCRIPT_PATH"
    environment = {
      HORUS_SCRIPT_PATH  = local.guest_baseline_script
      HORUS_SPEC_JSON    = jsonencode(self.input)
      HORUS_SSH_KEY_PATH = var.bootstrap_ssh_key_path
    }
  }
}
