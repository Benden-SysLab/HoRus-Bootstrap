locals {
  placement_spec = {
    vmid           = var.vmid
    hostname       = var.hostname
    template_vmid  = var.clone_template_id
    target_node    = var.target_node
    root_storage   = var.root_storage
    disk_size      = tonumber(var.disk_size)
    bridge         = var.bridge
    vlan_id        = var.vlan_id
    ip_address     = var.ip_address
    gateway        = var.gateway
    private_mounts = var.private_mounts
    features       = local.final_features
    allow_shutdown = var.allow_lxc_shutdown
    start_on_boot  = true
  }
  placement_script   = abspath("${path.module}/../../scripts/lxc_placement.ps1")
  placement_library  = abspath("${path.module}/../../scripts/lib/Horus.LxcPlacement.ps1")
  placement_revision = [filesha256(local.placement_script), filesha256(local.placement_library)]
}

# Provider 0.115.0 has no LXC rootfs move-volume API. This reusable completion
# barrier performs only same-node rootfs placement/growth, verifies the final
# state, and starts the CT last. Clone already targets the final node.
resource "terraform_data" "placement" {
  depends_on = [proxmox_virtual_environment_container.lxc_node]

  input = local.placement_spec
  triggers_replace = [
    local.placement_spec,
    local.placement_revision,
  ]

  lifecycle {
    replace_triggered_by = [proxmox_virtual_environment_container.lxc_node]
  }

  provisioner "local-exec" {
    interpreter = ["pwsh", "-NoLogo", "-NoProfile", "-NonInteractive", "-Command"]
    command     = "& $env:HORUS_SCRIPT_PATH"
    environment = {
      HORUS_SCRIPT_PATH  = local.placement_script
      HORUS_SPEC_JSON    = jsonencode(self.input)
      HORUS_SSH_KEY_PATH = var.bootstrap_ssh_key_path
    }
  }
}
