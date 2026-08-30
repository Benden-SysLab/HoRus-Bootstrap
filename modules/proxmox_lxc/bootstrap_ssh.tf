resource "terraform_data" "lxc_baseline_ssh" {
  count            = var.bootstrap_transport == "ssh" ? 1 : 0
  depends_on       = [proxmox_virtual_environment_container.lxc_node]
  triggers_replace = [var.baseline_version, proxmox_virtual_environment_container.lxc_node.id]

  connection {
    type        = "ssh"
    user        = "root"
    # Прямое подключение к самому контейнеру по IP-адресу
    host        = split("/", var.ip_address)[0]
    private_key = var.ssh_private_key != "" ? var.ssh_private_key : null
    password    = var.root_password
    timeout     = "5m"
  }

  # Копируем скрипт напрямую в контейнер
  provisioner "file" {
    content = templatefile("${path.module}/templates/lxc-bootstrap.sh.tftpl", {
      timezone         = var.timezone
      baseline_version = var.baseline_version
    })
    destination = "/tmp/lxc-bootstrap.sh"
  }

  # Делаем скрипт исполняемым и запускаем его внутри контейнера
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/lxc-bootstrap.sh",
      "/tmp/lxc-bootstrap.sh",
      "rm /tmp/lxc-bootstrap.sh"
    ]
  }
}
