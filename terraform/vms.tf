# Ubuntu VMs deployed from template ID 9000
resource "proxmox_vm_qemu" "ubuntu_web" {
  count       = 2
  name        = "web-${count.index + 1}"
  target_node = var.proxmox_node
  vmid        = 200 + count.index

  clone      = "ubuntu-24.04-hardened-template"
  full_clone = true

  cores   = 2
  sockets = 1
  memory  = 4096

  scsihw = "virtio-scsi-single"

  disk {
    slot    = "scsi0"
    type    = "disk"
    storage = "storage"
    size    = "50G"
  }

  disk {
    slot = "ide2"
    type = "cloudinit"
    storage = "storage"
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = var.vm_network_bridge
  }

  ipconfig0    = "ip=10.9.11.${20 + count.index}/24,gw=${var.vm_gateway}"
  nameserver   = "${var.vm_dns_primary} ${var.vm_dns_secondary}"
  searchdomain = var.vm_searchdomain

  sshkeys = file(pathexpand(var.ssh_public_key_file))

  agent = 1

  lifecycle {
    ignore_changes = [
      network,
      disk,
    ]
  }
}

# AlmaLinux VMs deployed from template ID 9001
resource "proxmox_vm_qemu" "almalinux_db" {
  count       = 2
  name        = "db-${count.index + 1}"
  target_node = var.proxmox_node
  vmid        = 210 + count.index

  clone      = "almalinux-10-hardened-template"
  full_clone = true

  cores   = 4
  sockets = 1
  memory  = 8192

  scsihw = "virtio-scsi-single"

  disk {
    slot    = "scsi0"
    type    = "disk"
    storage = "storage"
    size    = "50G"
  }

  disk {
    slot = "ide2"
    type = "cloudinit"
    storage = "storage"
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = var.vm_network_bridge
  }

  ipconfig0    = "ip=10.9.11.${22 + count.index}/24,gw=${var.vm_gateway}"
  nameserver   = "${var.vm_dns_primary} ${var.vm_dns_secondary}"
  searchdomain = var.vm_searchdomain

  sshkeys = file(pathexpand(var.ssh_public_key_file))

  agent = 1

  lifecycle {
    ignore_changes = [
      network,
      disk,
    ]
  }
}

# Single Ubuntu VM example
resource "proxmox_vm_qemu" "ubuntu_single" {
  name        = "app-server-01"
  target_node = var.proxmox_node
  vmid        = 220

  clone      = "ubuntu-24.04-hardened-template"
  full_clone = true

  cores   = 2
  sockets = 1
  memory  = 4096

  scsihw = "virtio-scsi-single"

  disk {
    slot    = "scsi0"
    type    = "disk"
    storage = "storage"
    size    = "50G"
  }

  disk {
    slot = "ide2"
    type = "cloudinit"
    storage = "storage"
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = var.vm_network_bridge
  }

  ipconfig0    = "ip=10.9.11.24/24,gw=${var.vm_gateway}"
  nameserver   = "${var.vm_dns_primary} ${var.vm_dns_secondary}"
  searchdomain = var.vm_searchdomain

  sshkeys = file(pathexpand(var.ssh_public_key_file))

  agent = 1

  lifecycle {
    ignore_changes = [
      network,
      disk,
    ]
  }
}
