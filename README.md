# Hardened Linux Infrastructure Deployment

Automated infrastructure deployment using Packer, Terraform, and Ansible for creating and deploying hardened Linux VM templates on Proxmox.

## Table of Contents

- [Overview](#overview)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Workflow](#workflow)
- [SSH Port Configuration](#ssh-port-configuration)
- [Documentation](#documentation)

## Overview

This repository contains the infrastructure-as-code components for deploying hardened Linux servers:

- **Packer** - Creates hardened VM templates (Ubuntu 24.04, AlmaLinux 10)
- **Terraform** - Deploys VMs from templates on Proxmox
- **Ansible** - Applies security hardening and application-specific configurations (via git submodule)

**Supported Distributions:**
- Ubuntu 24.04 LTS (Noble Numbat)
- AlmaLinux 10.x

**Target Platform:**
- Proxmox VE 9.x

## Repository Structure

```
hardened-linux-infra/
├── README.md                          # This file
├── DEPLOYMENT_WORKFLOW.md             # Detailed deployment workflow
├── PRE_INSTALLATION.md                # Pre-installation requirements
├── packer/
│   ├── ubuntu/
│   │   ├── ubuntu-24.04.pkr.hcl      # Ubuntu template definition
│   │   ├── http/
│   │   │   └── user-data             # Cloud-init user-data
│   │   └── variables/
│   │       └── ubuntu.pkrvars.hcl    # Ubuntu variables
│   └── almalinux/
│       ├── almalinux-10.pkr.hcl      # AlmaLinux template definition
│       └── variables/
│           └── almalinux.pkrvars.hcl # AlmaLinux variables
├── terraform/
│   ├── main.tf                        # Terraform main configuration
│   ├── vms.tf                         # VM resource definitions
│   ├── variables.tf                   # Variable definitions
│   ├── terraform.tfvars.example       # Example variables file
│   └── providers.tf                   # Provider configuration
└── playbooks/                         # Git submodule - Ansible playbooks
    └── hardened-linux/
        ├── ubuntu/                    # Ubuntu playbooks
        ├── almalinux/                 # AlmaLinux playbooks
        ├── templates/                 # Configuration templates
        ├── inventory/                 # Ansible inventory
        └── group_vars/                # Variable definitions
```

## Prerequisites

### Required Tools

1. **Packer** (v1.9.0+)
   ```bash
   # macOS
   brew install packer

   # Linux
   wget https://releases.hashicorp.com/packer/1.9.0/packer_1.9.0_linux_amd64.zip
   unzip packer_1.9.0_linux_amd64.zip
   sudo mv packer /usr/local/bin/
   ```

2. **Terraform** (v1.5.0+)
   ```bash
   # macOS
   brew install terraform

   # Linux
   wget https://releases.hashicorp.com/terraform/1.5.0/terraform_1.5.0_linux_amd64.zip
   unzip terraform_1.5.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   ```

3. **Ansible** (v2.12+)
   ```bash
   # macOS
   brew install ansible

   # Ubuntu/Debian
   sudo apt update && sudo apt install ansible

   # Using pip
   pip install ansible
   ```

4. **SSH Key Pair**
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/ansible_ed25519 -C "ansible@yourdomain.com"
   ```

### Proxmox Requirements

- Proxmox VE 9.x
- API token with appropriate permissions
- Storage configured (e.g., `storage`)
- Network bridge configured (e.g., `vmbr0`)
- ISO storage with Ubuntu and AlmaLinux installation images

## Quick Start

### 1. Clone Repository

```bash
git clone <repository-url> hardened-linux-infra
cd hardened-linux-infra
git submodule update --init --recursive
```

### 2. Configure Packer Variables

**Ubuntu:**
```bash
cp packer/ubuntu/variables/ubuntu.pkrvars.hcl.example packer/ubuntu/variables/ubuntu.pkrvars.hcl
# Edit the file with your Proxmox details
```

**AlmaLinux:**
```bash
cp packer/almalinux/variables/almalinux.pkrvars.hcl.example packer/almalinux/variables/almalinux.pkrvars.hcl
# Edit the file with your Proxmox details
```

### 3. Build Templates with Packer

```bash
# Build Ubuntu template
cd packer/ubuntu
packer build -var-file=variables/ubuntu.pkrvars.hcl ubuntu-24.04.pkr.hcl

# Build AlmaLinux template
cd ../almalinux
packer build -var-file=variables/almalinux.pkrvars.hcl almalinux-10.pkr.hcl
```

### 4. Configure Cloud-Init Drives

After Packer completes, add cloud-init drives to templates:

```bash
# Ubuntu template (ID 9000)
qm set 9000 --ide2 storage:cloudinit

# AlmaLinux template (ID 9001)
qm set 9001 --ide2 storage:cloudinit
```

### 5. Deploy VMs with Terraform

```bash
cd ../../terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your configuration

terraform init
terraform plan
terraform apply
```

### 6. Configure Ansible Inventory

```bash
cd ../playbooks/hardened-linux
cp inventory/production.yml.example inventory/production.yml
# Edit inventory/production.yml with deployed VM IPs
```

### 7. Run Ansible Playbooks

**Ubuntu servers:**
```bash
ansible-playbook -i inventory/production.yml ubuntu/01-basic-setup.yml --limit ubuntu_servers
```

**AlmaLinux servers:**
```bash
ansible-playbook -i inventory/production.yml almalinux/01-basic-setup.yml --limit almalinux_servers
```

## SSH Port Configuration

### Important: SSH Port Changes from 22 to 2222

The Ansible hardening playbooks change the SSH port from the default **22** to **2222** for enhanced security. This change happens during the first playbook run (`01-basic-setup.yml`).

**What you need to know:**

1. **Initial Connection**: Use port 22 for the first playbook run
   ```bash
   ansible-playbook -i inventory/production.yml ubuntu/01-basic-setup.yml
   ```

2. **After First Run**: Update your Ansible inventory to use port 2222
   ```yaml
   all:
     vars:
       ansible_port: 2222  # Add this line
   ```

3. **SSH Connections**: Always use port 2222 after hardening
   ```bash
   ssh -p 2222 sysadmin@server-ip
   ```

4. **Firewall Configuration**: Port 2222 is automatically opened in firewalld

5. **SELinux (AlmaLinux)**: Port 2222 is automatically added to SSH port context
   ```bash
   # This is done automatically by the playbook:
   semanage port -a -t ssh_port_t -p tcp 2222
   ```

**Troubleshooting SSH Port Issues:**

If you get connection refused on port 22 after hardening:
- This is expected behavior - the port has been changed to 2222
- Update your inventory file with `ansible_port: 2222`
- Connect using: `ssh -p 2222 user@host`

If SSH fails to restart on AlmaLinux:
- Check SELinux: `sudo ausearch -m avc -ts recent`
- Verify port is allowed: `sudo semanage port -l | grep ssh`
- The playbook handles this automatically, but manual intervention may be needed if playbook was interrupted

## Workflow

The complete deployment workflow consists of three stages:

### Stage 1: Template Creation (Packer)
- Builds base VM templates with cloud-init
- Installs qemu-guest-agent
- Cleans up network configuration
- Creates template on Proxmox

### Stage 2: VM Deployment (Terraform)
- Clones VMs from templates
- Configures network via cloud-init
- Sets up SSH keys
- Assigns static IP addresses

### Stage 3: Security Hardening (Ansible)
- Basic hardening (SSH, firewall, kernel)
- Application-specific configurations
- Service hardening
- Compliance enforcement

See [DEPLOYMENT_WORKFLOW.md](DEPLOYMENT_WORKFLOW.md) for detailed step-by-step instructions.

## Documentation

- [DEPLOYMENT_WORKFLOW.md](DEPLOYMENT_WORKFLOW.md) - Complete deployment workflow
- [PRE_INSTALLATION.md](PRE_INSTALLATION.md) - Pre-installation requirements and setup
- [playbooks/hardened-linux/README.md](playbooks/hardened-linux/README.md) - Ansible playbook documentation
- [playbooks/hardened-linux/QUICKSTART.md](playbooks/hardened-linux/QUICKSTART.md) - Quick reference guide

## Variables and Configuration

### Packer Variables

Located in `packer/*/variables/*.pkrvars.hcl`:

```hcl
proxmox_api_url          = "https://proxmox.example.com:8006/api2/json"
proxmox_api_token_id     = "terraform@pam!terraform-token"
proxmox_api_token_secret = "your-secret-here"
proxmox_node             = "pve"
template_name            = "ubuntu-24.04-hardened-template"
```

### Terraform Variables

Located in `terraform/terraform.tfvars`:

```hcl
proxmox_api_url      = "https://proxmox.example.com:8006/api2/json"
proxmox_node         = "pve"
vm_network_bridge    = "vmbr0"
vm_gateway           = "10.9.11.1"
ssh_public_key_file  = "~/.ssh/ansible_ed25519.pub"
```

### Ansible Variables

Located in `playbooks/hardened-linux/inventory/group_vars/`:

- `all.yml` - Common variables (SSH port, users, firewall)
- `ubuntu_servers.yml` - Ubuntu-specific settings
- `almalinux_servers.yml` - AlmaLinux-specific settings
- Role-specific files (`appservers.yml`, `dbservers.yml`, etc.)

## Maintenance

### Updating Templates

Rebuild templates periodically to include latest security patches:

```bash
cd packer/ubuntu
packer build -var-file=variables/ubuntu.pkrvars.hcl ubuntu-24.04.pkr.hcl
```

### Updating Playbooks

Pull latest playbook changes:

```bash
cd playbooks
git pull origin master
```

### Re-applying Hardening

Re-run playbooks to ensure compliance:

```bash
cd playbooks/hardened-linux
ansible-playbook -i inventory/production.yml ubuntu/01-basic-setup.yml --limit ubuntu_servers
```

## Troubleshooting

### Cloud-Init Network Issues

**Problem**: VMs keep template IP address instead of Terraform-configured IP

**Solution**:
1. Ensure cloud-init drive is added to template:
   ```bash
   qm set <template-id> --ide2 storage:cloudinit
   ```
2. Verify Terraform has explicit cloud-init disk block in `vms.tf`
3. Check Packer removed static network configs

### SELinux Port Issues (AlmaLinux)

**Problem**: SSH fails to start on port 2222

**Solution**:
```bash
sudo semanage port -a -t ssh_port_t -p tcp 2222
sudo systemctl restart sshd
```

### Terraform State Issues

**Problem**: Terraform state out of sync

**Solution**:
```bash
terraform refresh -var-file=terraform.tfvars
```

## License

Internal use only - follows company security policies and compliance requirements.
