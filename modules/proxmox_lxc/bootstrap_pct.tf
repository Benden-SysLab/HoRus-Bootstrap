resource "terraform_data" "lxc_baseline" {
  count            = var.bootstrap_transport == "pct" ? 1 : 0
  depends_on       = [proxmox_virtual_environment_container.lxc_node]
  triggers_replace = [var.baseline_version, proxmox_virtual_environment_container.lxc_node.id]

  connection {
    type        = "ssh"
    user        = "root"
    # Подключение к хосту Proxmox по IP-адресу, полученному из карты proxmox_nodes, чтобы избежать ошибок DNS-резолвинга
    host        = var.proxmox_ssh_host != "" ? var.proxmox_ssh_host : local.resolved_proxmox_host
    private_key = var.proxmox_ssh_private_key != "" ? var.proxmox_ssh_private_key : (var.ssh_private_key != "" ? var.ssh_private_key : null)
    password    = var.proxmox_ssh_password != "" ? var.proxmox_ssh_password : var.root_password
    timeout     = "3m"
  }

  # Рендерим шаблон lxc-bootstrap.sh.tftpl с динамическими переменными и сохраняем на хосте Proxmox
  provisioner "file" {
    content = templatefile("${path.module}/templates/lxc-bootstrap.sh.tftpl", {
      timezone         = var.timezone
      baseline_version = var.baseline_version
    })
    destination = "/tmp/lxc-bootstrap-${var.vmid}.sh"
  }

  # Копируем скрипт внутрь контейнера через pct push и выполняем его через pct exec (без сетевой зависимости)
  provisioner "remote-exec" {
    inline = [
      "pct push ${var.vmid} /tmp/lxc-bootstrap-${var.vmid}.sh /tmp/lxc-bootstrap.sh",
      "pct exec ${var.vmid} -- chmod +x /tmp/lxc-bootstrap.sh",
      "pct exec ${var.vmid} -- /tmp/lxc-bootstrap.sh",
      "pct exec ${var.vmid} -- rm /tmp/lxc-bootstrap.sh",
      "rm /tmp/lxc-bootstrap-${var.vmid}.sh"
    ]
  }
}
