# Automated VM Template Creation with Packer

This directory contains Packer templates for automating the creation of hardened VM templates for Ubuntu 24.04 and AlmaLinux 10. These templates automate all the manual steps described in [PRE_INSTALLATION.md](../PRE_INSTALLATION.md).

## Overview

Instead of manually installing and configuring each server, Packer automates:

- ✅ OS installation from ISO
- ✅ Custom disk partitioning with security mount options
- ✅ Network configuration (static IP, DNS, gateway)
- ✅ User creation with SSH keys
- ✅ Passwordless sudo setup
- ✅ SSH hardening (disable password auth)
- ✅ System updates
- ✅ Timezone configuration
- ✅ QEMU guest agent installation
- ✅ Cloud-init installation for future customization
- ✅ Template cleanup and optimization

## What Cannot Be Automated

The only aspect that still requires manual work is the **initial Proxmox/ESXi setup**:
- Installing Proxmox/ESXi hypervisor
- Creating API tokens/users
- Configuring network bridges
- Setting up storage pools

Everything else from OS installation onward is fully automated.

## Directory Structure

```
packer/
├── README.md                          # This file
├── PACKER_SETUP.md                    # Installation and detailed usage guide
│
├── ubuntu/
│   └── ubuntu-24.04.pkr.hcl          # Ubuntu 24.04 Packer template
│
├── almalinux/
│   └── almalinux-10.pkr.hcl          # AlmaLinux 10 Packer template
│
├── cloud-init/
│   ├── ubuntu/
│   │   ├── user-data                 # Ubuntu autoinstall configuration
│   │   └── meta-data                 # Ubuntu cloud-init metadata
│   └── almalinux/
│       ├── user-data                 # AlmaLinux cloud-init configuration
│       ├── meta-data                 # AlmaLinux cloud-init metadata
│       └── kickstart.cfg             # AlmaLinux kickstart installation
│
└── variables/
    ├── ubuntu.pkrvars.hcl.example    # Example Ubuntu variables
    └── almalinux.pkrvars.hcl.example # Example AlmaLinux variables
```

## Quick Start

### 1. Install Packer

See [PACKER_SETUP.md](PACKER_SETUP.md#installation) for detailed installation instructions.

**Quick install on Linux:**
```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install packer
```

**Quick install on macOS:**
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/packer
```

### 2. Configure Proxmox API Access

Create API token in Proxmox (see [PACKER_SETUP.md](PACKER_SETUP.md#proxmox-prerequisites)):

```bash
# SSH to Proxmox
pveum user add packer@pve
pveum user token add packer@pve packer-token --privsep=0
pveum acl modify / --user packer@pve --role PVEVMAdmin
pveum acl modify /storage --user packer@pve --role PVEDatastoreUser
```

Save the token secret securely.

### 3. Create Variables File

Create `variables/ubuntu.pkrvars.hcl` (do NOT commit to git):

```hcl
proxmox_url      = "https://your-proxmox.example.com:8006/api2/json"
proxmox_username = "packer@pve!packer-token"
proxmox_token    = "your-api-token-secret-here"
proxmox_node     = "pve"

vm_ip_address     = "10.0.1.100"
vm_gateway        = "10.0.1.1"
vm_dns_primary    = "8.8.8.8"
vm_admin_password = "TempPassword123!"
vm_ssh_public_key = "ssh-ed25519 AAAAC3... your-key@example.com"
```

See [PACKER_SETUP.md](PACKER_SETUP.md#create-variables-file) for all available variables.

### 4. Build Template

```bash
# Ubuntu 24.04
cd ubuntu
packer init ubuntu-24.04.pkr.hcl
packer validate -var-file=../variables/ubuntu.pkrvars.hcl ubuntu-24.04.pkr.hcl
packer build -var-file=../variables/ubuntu.pkrvars.hcl ubuntu-24.04.pkr.hcl

# AlmaLinux 10
cd ../almalinux
packer init almalinux-10.pkr.hcl
packer validate -var-file=../variables/almalinux.pkrvars.hcl almalinux-10.pkr.hcl
packer build -var-file=../variables/almalinux.pkrvars.hcl almalinux-10.pkr.hcl
```

Build time: **10-20 minutes** per template.

### 5. Use the Template

Clone the template to create new VMs:

```bash
# Clone via Proxmox CLI
qm clone 9000 100 --name web-server-01 --full
qm set 100 --ipconfig0 ip=10.0.1.10/24,gw=10.0.1.1
qm set 100 --sshkeys ~/.ssh/authorized_keys
qm start 100

# Or use Proxmox web UI: right-click template → Clone
```

## Features

### Disk Partitioning

Both templates create security-hardened partition layouts automatically:

```
/boot       1GB    ext4   (bootable)
/           20GB   ext4
/tmp        5GB    ext4   (nodev,nosuid,noexec)
/var        20GB   ext4   (nodev)
/var/log    10GB   ext4   (nodev,nosuid,noexec)
/home       10GB   ext4   (nodev,nosuid)
swap        4GB    swap
```

Mount options follow security best practices from [PRE_INSTALLATION.md](../PRE_INSTALLATION.md#disk-partitioning-plan).

### Security Configuration

Templates include:

- **SSH**: Password authentication disabled, key-only access
- **Root account**: Locked (Ubuntu and AlmaLinux)
- **Admin user**: Created with sudo access and SSH key
- **Firewall**: SSH allowed (can be hardened further with Ansible)
- **SELinux**: Enforcing (AlmaLinux)
- **Updates**: Latest packages installed during build
- **QEMU Agent**: Installed and enabled for Proxmox integration

### Cloud-init Support

Templates include cloud-init, allowing customization when cloning:

- Change hostname
- Set static IP or DHCP
- Add additional SSH keys
- Run custom scripts on first boot
- Inject user data

## Integration with Ansible Playbooks

After creating VMs from these templates:

1. **Templates are already hardened** with basic security (partitions, SSH, users)
2. **Apply Ansible playbooks** from [../](../) for additional hardening:
   - CIS benchmarks
   - Audit logging
   - Firewall rules
   - Security updates
   - Monitoring setup

**Workflow:**

```bash
# 1. Build template with Packer (once)
packer build -var-file=../variables/ubuntu.pkrvars.hcl ubuntu-24.04.pkr.hcl

# 2. Clone template to create VM
qm clone 9000 100 --name app-server-01 --full
qm set 100 --ipconfig0 ip=10.0.1.10/24,gw=10.0.1.1
qm start 100

# 3. Wait for VM to boot (30-60 seconds)

# 4. Apply Ansible hardening playbooks
cd ../../
ansible-playbook -i inventory/hosts.yml ubuntu/01-basic-setup.yml
ansible-playbook -i inventory/hosts.yml ubuntu/02-security-hardening.yml
```

## Variables Reference

### Common Variables (Both Templates)

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `proxmox_url` | Proxmox API URL | - | Yes |
| `proxmox_username` | API token username | - | Yes |
| `proxmox_token` | API token secret | - | Yes |
| `proxmox_node` | Proxmox node name | `pve` | No |
| `vm_id` | Template VM ID | `9000`/`9001` | No |
| `vm_name` | Template name | `ubuntu-24.04-hardened-template` | No |
| `vm_cpu_cores` | CPU cores | `2` | No |
| `vm_memory` | RAM in MB | `4096` | No |
| `vm_disk_size` | Disk size | `80G` | No |
| `vm_ip_address` | Build IP address | `10.0.1.100` | No |
| `vm_gateway` | Network gateway | `10.0.1.1` | No |
| `vm_dns_primary` | Primary DNS | `8.8.8.8` | No |
| `vm_admin_user` | Admin username | `sysadmin` | No |
| `vm_admin_password` | Temporary password | - | Yes |
| `vm_ssh_public_key` | SSH public key | - | Yes |
| `vm_timezone` | System timezone | `UTC` | No |

### Ubuntu-Specific Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `iso_url` | Ubuntu ISO URL | Ubuntu 24.04.1 URL |
| `iso_checksum` | ISO checksum | `sha256:e240e4b8...` |

### AlmaLinux-Specific Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `iso_url` | AlmaLinux ISO URL | AlmaLinux 10 boot ISO |
| `iso_checksum` | ISO checksum | Checksum file URL |

See [PACKER_SETUP.md](PACKER_SETUP.md#create-variables-file) for complete variable documentation.

## Customization

### Change Disk Partitioning

Edit the cloud-init configuration:

**Ubuntu**: [cloud-init/ubuntu/user-data](cloud-init/ubuntu/user-data)
**AlmaLinux**: [cloud-init/almalinux/kickstart.cfg](cloud-init/almalinux/kickstart.cfg)

### Add Additional Packages

Edit the Packer template provisioners:

**Ubuntu**: [ubuntu/ubuntu-24.04.pkr.hcl](ubuntu/ubuntu-24.04.pkr.hcl)
```hcl
provisioner "shell" {
  inline = [
    "sudo apt-get install -y docker.io postgresql-client"
  ]
}
```

**AlmaLinux**: [almalinux/almalinux-10.pkr.hcl](almalinux/almalinux-10.pkr.hcl)
```hcl
provisioner "shell" {
  inline = [
    "sudo dnf install -y docker postgresql"
  ]
}
```

### Change Network Configuration

Modify variables in your `.pkrvars.hcl` file or edit cloud-init templates directly.

## Troubleshooting

See [PACKER_SETUP.md](PACKER_SETUP.md#troubleshooting) for detailed troubleshooting.

**Common issues:**

| Problem | Solution |
|---------|----------|
| SSH timeout | Check IP address is available, verify network config |
| ISO not found | Pre-download ISO or check internet connectivity |
| API connection failed | Verify token and permissions |
| Boot command timeout | Check ISO URL matches boot command |

**Debug mode:**

```bash
PACKER_LOG=1 packer build -var-file=../variables/ubuntu.pkrvars.hcl ubuntu-24.04.pkr.hcl
```

## CI/CD Integration

### Automated Template Rebuilds

You can automate monthly template rebuilds with a cron job or CI/CD pipeline:

```bash
#!/bin/bash
# rebuild-templates.sh

cd /path/to/packer/ubuntu
packer build -force -var-file=../variables/ubuntu.pkrvars.hcl ubuntu-24.04.pkr.hcl

cd ../almalinux
packer build -force -var-file=../variables/almalinux.pkrvars.hcl almalinux-10.pkr.hcl
```

### GitHub Actions Example

```yaml
name: Rebuild VM Templates

on:
  schedule:
    - cron: '0 2 1 * *'  # Monthly on 1st at 2am
  workflow_dispatch:

jobs:
  build-templates:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-packer@v3

      - name: Build Ubuntu Template
        env:
          PROXMOX_TOKEN: ${{ secrets.PROXMOX_TOKEN }}
        run: |
          cd ansible/playbooks/hardened-linux/packer/ubuntu
          packer init .
          packer build -var-file=../variables/ubuntu.pkrvars.hcl ubuntu-24.04.pkr.hcl
```

## Comparison: Manual vs Packer

| Task | Manual Time | Packer Time | Notes |
|------|-------------|-------------|-------|
| OS Installation | 15-30 min | Automated | Click-through vs scripted |
| Disk Partitioning | 10-15 min | Automated | Error-prone vs reproducible |
| Network Config | 5-10 min | Automated | Per-server vs template |
| User Setup | 5 min | Automated | SSH keys, sudo |
| Package Updates | 5-10 min | Automated | Included in build |
| SSH Hardening | 5 min | Automated | Consistent config |
| **Total per server** | **45-75 min** | **0 min** | Just clone template |
| **Template build** | - | **15-20 min** | One-time per update |

**Time savings for 10 servers:**
- Manual: 7.5 - 12.5 hours
- Packer: 15-20 minutes + 10 × 2 min cloning = ~35 minutes

## Best Practices

1. **Version Control**: Commit Packer templates, exclude `.pkrvars.hcl` files
2. **Secrets Management**: Use environment variables or Vault for tokens
3. **Regular Rebuilds**: Rebuild templates monthly for security updates
4. **Testing**: Test templates in dev before production use
5. **Documentation**: Document customizations in comments
6. **Backup**: Keep snapshots of working templates
7. **Naming**: Use versioned names (e.g., `ubuntu-24.04-v2024.11`)

## Next Steps

1. **Install Packer**: Follow [PACKER_SETUP.md](PACKER_SETUP.md)
2. **Configure Proxmox**: Create API token and set permissions
3. **Create variables file**: Copy example and customize
4. **Build templates**: Run `packer build` commands
5. **Test**: Clone template and verify configuration
6. **Apply Ansible**: Use playbooks from [../](../) for additional hardening

## Resources

- [Packer Setup Guide](PACKER_SETUP.md) - Detailed installation and usage
- [Pre-Installation Guide](../PRE_INSTALLATION.md) - Manual installation reference
- [Packer Documentation](https://www.packer.io/docs)
- [Cloud-init Documentation](https://cloudinit.readthedocs.io/)
- [Proxmox Packer Plugin](https://www.packer.io/plugins/builders/proxmox/iso)

## Support

For issues or questions:

1. Check [PACKER_SETUP.md](PACKER_SETUP.md#troubleshooting)
2. Enable debug logging: `PACKER_LOG=1`
3. Review Proxmox task logs in web UI
4. Check cloud-init logs: `/var/log/cloud-init.log`

## License

These templates are part of the infrastructure automation toolkit and follow the same license as the parent repository.
