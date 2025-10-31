output "ubuntu_web_servers" {
  description = "Ubuntu web server details"
  value = {
    for idx, vm in proxmox_vm_qemu.ubuntu_web : idx => {
      name = vm.name
      id   = vm.vmid
      ip   = "10.9.11.${20 + idx}"
    }
  }
}

output "almalinux_db_servers" {
  description = "AlmaLinux database server details"
  value = {
    for idx, vm in proxmox_vm_qemu.almalinux_db : idx => {
      name = vm.name
      id   = vm.vmid
      ip   = "10.9.11.${22 + idx}"
    }
  }
}

output "ubuntu_app_server" {
  description = "Ubuntu application server details"
  value = {
    name = proxmox_vm_qemu.ubuntu_single.name
    id   = proxmox_vm_qemu.ubuntu_single.vmid
    ip   = "10.9.11.24"
  }
}

output "ansible_inventory" {
  description = "Ansible inventory in YAML format"
  value = <<-EOT
all:
  vars:
    ansible_user: sysadmin
    ansible_ssh_private_key_file: ~/.ssh/id_ed25519
    ansible_python_interpreter: /usr/bin/python3
    ansible_become: true

  children:
    web_servers:
      hosts:
${join("\n", [for idx, vm in proxmox_vm_qemu.ubuntu_web : "        ${vm.name}:\n          ansible_host: 10.9.11.${20 + idx}"])}

    db_servers:
      hosts:
${join("\n", [for idx, vm in proxmox_vm_qemu.almalinux_db : "        ${vm.name}:\n          ansible_host: 10.9.11.${22 + idx}"])}

    app_servers:
      hosts:
        ${proxmox_vm_qemu.ubuntu_single.name}:
          ansible_host: 10.9.11.24

    ubuntu_servers:
      children:
        web_servers:
        app_servers:

    almalinux_servers:
      children:
        db_servers:
EOT
}
