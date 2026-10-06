provider "proxmox" {
  endpoint  = "https://127.0.0.1:8006/api2/json"
  api_token = "test@pam!terraform=00000000-0000-0000-0000-000000000000"
  insecure  = true
}

variables {
  target_node            = "horus-pmx-node04"
  vmid                   = 405
  hostname               = "horus-s3-srv01"
  cores                  = 2
  memory                 = 2048
  disk_size              = "16"
  root_storage           = "local-lvm"
  bridge                 = "vmbr0"
  vlan_id                = 150
  ip_address             = "198.51.100.88/28"
  gateway                = "198.51.100.81"
  dns_servers            = ["203.0.113.53"]
  feature_profile        = "storage"
  bootstrap_ssh_key_path = "C:/test/key"
  private_mounts = [{
    datastore_id = "logs-data"
    path         = "/data/example/logs"
    size         = "0"
  }]
}

run "two_phase_final_node_clone_and_managed_private_volume" {
  command = plan
  module {
    source = "./modules/proxmox_lxc"
  }

  assert {
    condition     = proxmox_virtual_environment_container.lxc_node.node_name == "horus-pmx-node04" && proxmox_virtual_environment_container.lxc_node.clone[0].node_name == "horus-pmx-node03" && proxmox_virtual_environment_container.lxc_node.clone[0].datastore_id == "storage-infra"
    error_message = "LXC must clone Golden 9001 directly to the final node through shared storage-infra."
  }
  assert {
    condition     = !proxmox_virtual_environment_container.lxc_node.started && proxmox_virtual_environment_container.lxc_node.start_on_boot && proxmox_virtual_environment_container.lxc_node.disk[0].datastore_id == "local-lvm" && proxmox_virtual_environment_container.lxc_node.disk[0].size == 16
    error_message = "Provider must leave LXC stopped for placement while declaring final local-lvm/size and autostart."
  }
  assert {
    condition     = proxmox_virtual_environment_container.lxc_node.mount_point[0].volume == "logs-data" && proxmox_virtual_environment_container.lxc_node.mount_point[0].size == "0T" && proxmox_virtual_environment_container.lxc_node.mount_point[0].path == "/data/example/logs"
    error_message = "Private state must use a Proxmox-managed directory volume with canonical zero-size representation."
  }
  assert {
    condition     = terraform_data.placement.input.target_node == "horus-pmx-node04" && terraform_data.placement.input.start_on_boot
    error_message = "Placement barrier must verify the final node and autostart policy."
  }
}

run "lxc_cannot_shrink_below_golden" {
  command = plan
  module {
    source = "./modules/proxmox_lxc"
  }
  variables {
    disk_size = "7"
  }
  expect_failures = [var.disk_size]
}
