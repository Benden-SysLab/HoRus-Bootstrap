locals {
  guest_baseline_spec = {
    vmid                     = var.vmid
    hostname                 = var.hostname
    template_vmid            = var.clone_template_id
    target_node              = var.target_node
    template_host_key_sha256 = var.clone_template_host_key_sha256
    timezone                 = var.timezone
  }
  guest_baseline_script   = abspath("${path.module}/../../scripts/lxc_guest_baseline.ps1")
  guest_baseline_library  = abspath("${path.module}/../../scripts/lib/Horus.LxcGuestBaseline.ps1")
  guest_baseline_revision = [filesha256(local.guest_baseline_script), filesha256(local.guest_baseline_library)]
}

# The former SSH-only barrier is now the combined pre-start baseline. Preserve
# its state identity so this refactor does not execute guest changes on running
# containers; a real LXC replacement still recreates and runs the barrier.
moved {
  from = terraform_data.ssh_identity
  to   = terraform_data.guest_baseline
}

# One pre-start barrier handles the small guest baseline that the provider
# cannot express: unique SSH host keys, Europe/Moscow and Jenkins sudo.
resource "terraform_data" "guest_baseline" {
  depends_on = [proxmox_virtual_environment_container.lxc_node]

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
