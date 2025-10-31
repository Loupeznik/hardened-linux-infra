packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "proxmox_url" {
  type        = string
  description = "Proxmox API URL (e.g., https://proxmox.example.com:8006/api2/json)"
}

variable "proxmox_username" {
  type        = string
  description = "Proxmox username (e.g., root@pam or terraform@pve)"
}

variable "proxmox_token" {
  type        = string
  sensitive   = true
  description = "Proxmox API token"
}

variable "proxmox_node" {
  type        = string
  description = "Proxmox node name"
  default     = "pve"
}

variable "proxmox_storage_pool" {
  type        = string
  description = "Storage pool for VM disk"
  default     = "local-lvm"
}

variable "proxmox_iso_storage" {
  type        = string
  description = "Storage pool for ISO files"
  default     = "local"
}

variable "vm_id" {
  type        = number
  description = "VM template ID"
  default     = 9001
}

variable "vm_name" {
  type        = string
  description = "VM template name"
  default     = "almalinux-10-hardened-template"
}

variable "vm_cpu_cores" {
  type        = number
  description = "Number of CPU cores"
  default     = 2
}

variable "vm_cpu_type" {
  type        = string
  description = "CPU type"
  default     = "host"
}

variable "vm_memory" {
  type        = number
  description = "Memory in MB"
  default     = 4096
}

variable "vm_disk_size" {
  type        = string
  description = "Disk size (e.g., 80G)"
  default     = "80G"
}

variable "vm_disk_type" {
  type        = string
  description = "Disk type"
  default     = "scsi"
}

variable "vm_network_bridge" {
  type        = string
  description = "Network bridge"
  default     = "vmbr0"
}

variable "vm_network_model" {
  type        = string
  description = "Network model"
  default     = "virtio"
}

variable "vm_ip_address" {
  type        = string
  description = "Static IP address for the template VM"
  default     = "10.0.1.101"
}

variable "vm_network_prefix" {
  type        = number
  description = "Network prefix (CIDR notation)"
  default     = 24
}

variable "vm_gateway" {
  type        = string
  description = "Network gateway"
  default     = "10.0.1.1"
}

variable "vm_dns_primary" {
  type        = string
  description = "Primary DNS server"
  default     = "8.8.8.8"
}

variable "vm_dns_secondary" {
  type        = string
  description = "Secondary DNS server"
  default     = "8.8.4.4"
}

variable "vm_dns_domain" {
  type        = string
  description = "DNS search domain"
  default     = "example.com"
}

variable "vm_hostname" {
  type        = string
  description = "VM hostname"
  default     = "almalinux-template"
}

variable "vm_admin_user" {
  type        = string
  description = "Admin username"
  default     = "sysadmin"
}

variable "vm_admin_password" {
  type        = string
  sensitive   = true
  description = "Admin user password (temporary, will be disabled after SSH key setup)"
}

variable "vm_ssh_public_key" {
  type        = string
  description = "SSH public key for admin user"
}

variable "vm_ssh_private_key_file" {
  type        = string
  description = "Path to SSH private key file for Packer to connect to VM"
  default     = "~/.ssh/id_ed25519"
}

variable "vm_timezone" {
  type        = string
  description = "Timezone (e.g., America/New_York, Europe/Prague)"
  default     = "UTC"
}

variable "iso_filename" {
  type        = string
  description = "Filename of the pre-uploaded ISO on Proxmox storage"
  default     = "AlmaLinux-10-latest-x86_64-dvd.iso"
}

locals {
  vm_admin_password_hash = bcrypt(var.vm_admin_password, 10)
}

source "proxmox-iso" "almalinux-10" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  vm_id       = var.vm_id
  vm_name     = var.vm_name
  template_description = "AlmaLinux 10 hardened template - Built with Packer on ${formatdate("YYYY-MM-DD", timestamp())}"

  boot_iso {
    iso_file = "${var.proxmox_iso_storage}:iso/${var.iso_filename}"
    unmount  = true
  }

  qemu_agent = true
  scsi_controller = "virtio-scsi-single"

  cores  = var.vm_cpu_cores
  cpu_type = var.vm_cpu_type
  memory = var.vm_memory

  disks {
    type              = var.vm_disk_type
    disk_size         = var.vm_disk_size
    storage_pool      = var.proxmox_storage_pool
    format            = "raw"
    io_thread         = true
    discard           = true
  }

  network_adapters {
    model    = var.vm_network_model
    bridge   = var.vm_network_bridge
    firewall = false
  }

  boot_wait = "10s"
  boot_command = [
    "<up><wait1>",
    "e<wait1>",
    "<down><down><end>",
    " inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg<wait1>",
    "<f10>"
  ]

  http_content = {
    "/ks.cfg" = templatefile("${path.root}/../cloud-init/almalinux/kickstart.cfg", {
      vm_hostname             = var.vm_hostname
      vm_admin_user           = var.vm_admin_user
      vm_admin_password_hash  = local.vm_admin_password_hash
      vm_ssh_public_key       = var.vm_ssh_public_key
      vm_timezone             = var.vm_timezone
      vm_ip_address           = var.vm_ip_address
      vm_network_prefix       = var.vm_network_prefix
      vm_gateway              = var.vm_gateway
      vm_dns_primary          = var.vm_dns_primary
      vm_dns_secondary        = var.vm_dns_secondary
      vm_dns_domain           = var.vm_dns_domain
    })
  }

  ssh_username             = var.vm_admin_user
  ssh_private_key_file     = pathexpand(var.vm_ssh_private_key_file)
  ssh_timeout              = "20m"
  ssh_handshake_attempts   = 100
}

build {
  sources = ["source.proxmox-iso.almalinux-10"]

  provisioner "shell" {
    inline = [
      "sudo dnf update -y",
      "sudo dnf install -y qemu-guest-agent cloud-init cloud-utils-growpart python3",
      "sudo systemctl enable qemu-guest-agent",
      "sudo systemctl enable cloud-init",
      "sudo rm -f /etc/sysconfig/network-scripts/ifcfg-*",
      "sudo cloud-init clean --logs --seed",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo mkdir -p /var/lib/dbus",
      "sudo rm -f /var/lib/dbus/machine-id",
      "sudo ln -s /etc/machine-id /var/lib/dbus/machine-id",
      "sudo sync"
    ]
  }

  provisioner "shell" {
    inline = [
      "echo 'Cleaning up...'",
      "sudo dnf clean all",
      "sudo rm -rf /tmp/*",
      "sudo rm -rf /var/tmp/*",
      "sudo rm -f /var/log/wtmp /var/log/btmp",
      "sudo truncate -s 0 /var/log/lastlog",
      "sudo find /var/log -type f -name '*.log' -exec truncate -s 0 {} \\;",
      "sudo rm -f /root/.bash_history",
      "sudo rm -f /home/${var.vm_admin_user}/.bash_history",
      "sudo rm -f ~/.bash_history"
    ]
  }
}
