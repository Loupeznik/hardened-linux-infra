# Hardened VM Deployment Workflow

Complete guide for deploying hardened VMs using Packer, Terraform, and Ansible.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Step 1: Build Base Templates with Packer](#step-1-build-base-templates-with-packer)
- [Step 2: Deploy VMs with Terraform](#step-2-deploy-vms-with-terraform)
- [Step 3: Harden VMs with Ansible](#step-3-harden-vms-with-ansible)
- [Complete Example](#complete-example)
- [Troubleshooting](#troubleshooting)

## Overview

This workflow uses three tools in sequence:

```
┌─────────┐      ┌───────────┐      ┌─────────┐      ┌──────────────┐
│ Packer  │ ───> │ Templates │ ───> │Terraform│ ───> │   Ansible    │
│         │      │ (VM 9000, │      │         │      │              │
│ Build   │      │  VM 9001) │      │ Deploy  │      │   Harden     │
└─────────┘      └───────────┘      └─────────┘      └──────────────┘
                                                              │
                                                              v
                                                      ┌──────────────┐
                                                      │  Production  │
                                                      │  Ready VMs   │
                                                      └──────────────┘
```

**Packer** → Creates minimal, pre-configured OS templates
**Terraform** → Deploys VMs from templates with desired specs
**Ansible** → Applies security hardening and application configuration

## Prerequisites

### Required Tools

**On your bastion/automation host:**

- Packer >= 1.9.0
- Terraform >= 1.5.0
- Ansible >= 2.15
- SSH access to Proxmox
- SSH key pair configured

### Proxmox Setup

1. **API Tokens Created:**
   - `packer@pve!packer-token` - for Packer
   - `terraform-prov@pve!terraform-deploy-token` - for Terraform

2. **Permissions Granted:**

   **For Packer:**
   ```bash
   # Create custom role with required privileges
   pveum role add PackerRole -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt SDN.Use"

   # Create user and assign role
   pveum user add packer@pve --password <strong-password>
   pveum aclmod / --user packer@pve --role PackerRole

   # Create API token
   pveum user token add packer@pve packer-token

   # Grant permissions to token (use single quotes to avoid bash history expansion)
   pveum aclmod / --tokens 'packer@pve!packer-token' --role PackerRole
   ```

   **For Terraform:**
   ```bash
   # Create custom role with required privileges (Proxmox 9)
   pveum role add TerraformProv -privs "Datastore.AllocateSpace Datastore.Audit Pool.Allocate SDN.Use Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.PowerMgmt VM.GuestAgent.Audit VM.GuestAgent.Unrestricted"

   # Create user and assign role
   pveum user add terraform-prov@pve --password <strong-password>
   pveum aclmod / --user terraform-prov@pve --role TerraformProv

   # Create API token
   pveum user token add terraform-prov@pve terraform-deploy-token

   # Grant permissions to token (use single quotes to avoid bash history expansion)
   pveum aclmod / --tokens 'terraform-prov@pve!terraform-deploy-token' --role TerraformProv
   ```

   **Note for Proxmox 8 users:** Replace the privileges with: `"Datastore.AllocateSpace Datastore.Audit Pool.Allocate SDN.Use Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt VM.GuestAgent.Audit VM.GuestAgent.Unrestricted"` (includes `VM.Monitor` instead of being removed)

   **Important Notes:**
   - Use single quotes around token IDs to prevent bash from interpreting the `!` character
   - Tokens have privilege separation enabled by default (`privsep=1`)
   - You MUST grant ACL permissions directly to the token, not just the user
   - Alternative: disable privilege separation with `pveum user token modify <user>!<token> --privsep 0` (less secure)

3. **ISOs Uploaded:**
   ```bash
   # On Proxmox host
   cd /var/lib/vz/template/iso
   wget https://releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso
   wget https://repo.almalinux.org/almalinux/10/isos/x86_64/AlmaLinux-10-latest-x86_64-dvd.iso
   ```

## Step 1: Build Base Templates with Packer

### 1.1 Configure Variables

Create your Packer variables file:

```bash
cd ~/automation/hardened-linux/packer/variables
cp ubuntu.pkrvars.hcl.example ubuntu.pkrvars.hcl
cp almalinux.pkrvars.hcl.example almalinux.pkrvars.hcl
```

Edit the files with your environment details:

```hcl
# ubuntu.pkrvars.hcl
proxmox_url      = "https://your-proxmox:8006/api2/json"
proxmox_username = "packer@pve!packer-token"
proxmox_token    = "your-token-here"
proxmox_node     = "pve-prod-02"  # Your actual node name

vm_network_bridge = "vnet0"
vm_ip_address     = "10.9.11.80"
vm_ssh_public_key = "ssh-ed25519 AAAA... your-key"
# ... rest of configuration
```

### 1.2 Build Ubuntu Template

```bash
cd ~/automation/hardened-linux/packer/ubuntu

# Initialize Packer
packer init ubuntu-24.04.pkr.hcl

# Validate configuration
packer validate -var-file=../variables/ubuntu.pkrvars.hcl ubuntu-24.04.pkr.hcl

# Build template (10-15 minutes)
packer build -var-file=../variables/ubuntu.pkrvars.hcl ubuntu-24.04.pkr.hcl
```

**Result:** VM template created with ID 9000

### 1.3 Build AlmaLinux Template

```bash
cd ~/automation/hardened-linux/packer/almalinux

# Initialize Packer
packer init almalinux-10.pkr.hcl

# Validate configuration
packer validate -var-file=../variables/almalinux.pkrvars.hcl almalinux-10.pkr.hcl

# Build template (15-20 minutes)
packer build -var-file=../variables/almalinux.pkrvars.hcl almalinux-10.pkr.hcl
```

**Result:** VM template created with ID 9001

### 1.4 Verify Templates

```bash
# On Proxmox host or via SSH
ssh root@your-proxmox "qm list | grep -E '9000|9001'"

# Expected output:
#       9000 ubuntu-24.04-hardened-template    0      4096       50.00        0
#       9001 almalinux-10-hardened-template    0      4096       80.00        0
```

## Step 2: Deploy VMs with Terraform

### 2.1 Setup Terraform

```bash
cd ~/automation/hardened-linux/terraform

# Copy example variables
cp terraform.tfvars.example terraform.tfvars

# Edit with your credentials
vim terraform.tfvars
```

**terraform.tfvars:**
```hcl
proxmox_url          = "https://65.109.98.48:8006/api2/json"
proxmox_token_id     = "terraform-prov@pve!terraform-deploy-token"
proxmox_token_secret = "your-terraform-token-secret-here"
proxmox_node         = "pve-prod-02"

ssh_public_key_file = "~/.ssh/id_ed25519.pub"

vm_network_bridge = "vnet0"
vm_gateway        = "10.9.11.0"
vm_dns_primary    = "8.8.8.8"
vm_dns_secondary  = "8.8.4.4"
vm_searchdomain   = "dzarsky.eu"
```

### 2.2 Initialize Terraform

```bash
# Download provider plugins
terraform init
```

### 2.3 Plan Deployment

```bash
# Review what will be created
terraform plan

# Expected output shows:
# - 2x Ubuntu web servers (web-1, web-2)
# - 2x AlmaLinux database servers (db-1, db-2)
# - 1x Ubuntu app server (app-server-01)
```

### 2.4 Deploy VMs

```bash
# Deploy all VMs
terraform apply

# Type 'yes' when prompted

# Deployment takes 2-3 minutes
```

### 2.5 Verify Deployment

```bash
# Show created VMs
terraform show

# Get VM details
terraform output

# Output includes:
# - VM names and IDs
# - IP addresses
# - Ansible inventory format
```

## Step 3: Harden VMs with Ansible

After Terraform deployment is complete, update the inventory file at `inventory/production.yml` with the deployed VM hostnames and IP addresses before proceeding with Ansible hardening.

### 3.1 Verify Connectivity

```bash
cd ~/automation/hardened-linux

# Test SSH connectivity to all hosts
ansible all -i inventory/production.yml -m ping

# Expected: All hosts should return pong
```

### 3.2 Apply Base Hardening (Ubuntu)

```bash
# Harden Ubuntu servers (web + app)
ansible-playbook -i inventory/production.yml \
  ubuntu/01-basic-setup.yml \
  --limit ubuntu_servers
```

### 3.3 Apply Base Hardening (AlmaLinux)

```bash
# Harden AlmaLinux database servers
ansible-playbook -i inventory/production.yml \
  almalinux/01-basic-setup.yml \
  --limit almalinux_servers
```

### 3.4 Reboot Servers

After basic hardening completes, reboot all servers:

```bash
# Reboot all servers
ansible all -i inventory/production.yml -b -m reboot

# Wait for servers to come back (2-3 minutes)
# IMPORTANT: SSH port will change to 2222 after reboot
```

### 3.5 Apply Role-Specific Configuration

**For web servers (Ubuntu):**
```bash
# Note: Update SSH port to 2222 in your SSH config or use -e ansible_port=2222
ansible-playbook -i inventory/production.yml \
  ubuntu/02-appserver.yml \
  --limit web_servers \
  -e ansible_port=2222
```

**For database servers (AlmaLinux):**
```bash
ansible-playbook -i inventory/production.yml \
  almalinux/03-dbserver.yml \
  --limit db_servers \
  -e ansible_port=2222
```

**For application servers (Ubuntu):**
```bash
ansible-playbook -i inventory/production.yml \
  ubuntu/02-appserver.yml \
  --limit app_servers \
  -e ansible_port=2222
```

## Complete Example

### End-to-End Deployment

```bash
#!/bin/bash
# deploy-infrastructure.sh

set -e

echo "=== Building Packer Templates ==="
cd ~/automation/hardened-linux/packer/ubuntu
packer build -var-file=../variables/ubuntu.pkrvars.hcl ubuntu-24.04.pkr.hcl

cd ~/automation/hardened-linux/packer/almalinux
packer build -var-file=../variables/almalinux.pkrvars.hcl almalinux-10.pkr.hcl

echo "=== Deploying VMs with Terraform ==="
cd ~/automation/hardened-linux/terraform
terraform apply -auto-approve

echo "=== Waiting for VMs to boot ==="
sleep 30

echo "=== Generating Ansible Inventory ==="
terraform output -raw ansible_inventory > ../inventory/production.yml

echo "=== Testing Connectivity ==="
cd ~/automation/hardened-linux
ansible all -i inventory/production.yml -m ping

echo "=== Applying Hardening ==="
ansible-playbook -i inventory/production.yml ubuntu/01-basic-setup.yml --limit ubuntu_servers
ansible-playbook -i inventory/production.yml almalinux/01-basic-setup.yml --limit almalinux_servers

echo "=== Rebooting Servers ==="
ansible all -i inventory/production.yml -b -m reboot
sleep 120

echo "=== Deployment Complete ==="
terraform output
```

### Customizing for Your Use Case

**Example: Deploy only web servers**

Edit `terraform/vms.tf` to comment out unwanted resources:

```hcl
# Comment out db_servers and app_servers
# resource "proxmox_vm_qemu" "almalinux_db" { ... }
# resource "proxmox_vm_qemu" "ubuntu_single" { ... }

# Keep only web_servers
resource "proxmox_vm_qemu" "ubuntu_web" {
  count = 3  # Deploy 3 web servers instead of 2
  # ...
}
```

**Example: Different VM specs per environment**

Create separate `.tfvars` files:

```bash
# terraform/production.tfvars
proxmox_token_id = "terraform-prov@pve!terraform-deploy-token"
# ... production settings

# terraform/staging.tfvars
proxmox_token_id = "terraform-prov@pve!terraform-staging-token"
# ... staging settings

# Deploy to staging
terraform apply -var-file=staging.tfvars

# Deploy to production
terraform apply -var-file=production.tfvars
```

## Maintenance and Updates

### Updating Templates

When you need to rebuild templates (e.g., new OS version):

```bash
# 1. Destroy old template
ssh root@proxmox "qm destroy 9000"

# 2. Rebuild with Packer
cd ~/automation/hardened-linux/packer/ubuntu
packer build -var-file=../variables/ubuntu.pkrvars.hcl ubuntu-24.04.pkr.hcl

# 3. Existing deployed VMs are NOT affected
# 4. New deployments will use the new template
```

### Scaling Up

```bash
# Add more VMs by increasing count
vim terraform/vms.tf

# Change: count = 2
# To:     count = 5

# Apply changes
cd terraform
terraform apply

# Terraform will create 3 additional VMs
```

### Scaling Down

```bash
# Reduce count in vms.tf
vim terraform/vms.tf

# Change: count = 5
# To:     count = 2

# Apply (will destroy 3 VMs)
cd terraform
terraform apply
```

### Complete Teardown

```bash
# Destroy all Terraform-managed VMs
cd ~/automation/hardened-linux/terraform
terraform destroy

# This does NOT destroy the Packer templates (9000, 9001)
```

## Troubleshooting

### Packer Issues

**Issue: Boot command timeout**
```bash
# Solution: Increase boot_wait in .pkr.hcl
boot_wait = "15s"  # Instead of 10s
```

**Issue: SSH authentication failed**
```bash
# Verify SSH key is correct in variables
cat ~/.ssh/id_ed25519.pub

# Should match vm_ssh_public_key in .pkrvars.hcl
```

**Issue: ISO not found**
```bash
# Verify ISO is uploaded to Proxmox
ssh root@proxmox "ls -lh /var/lib/vz/template/iso/"
```

### Terraform Issues

**Issue: Template not found**
```bash
# Error: clone target 'ubuntu-24.04-hardened-template' not found

# Solution: Check template exists
ssh root@proxmox "qm list | grep template"

# Ensure template name in vms.tf matches exactly
```

**Issue: IP address conflict**
```bash
# Solution: Check no existing VMs use the same IPs
# Change IP ranges in vms.tf if needed
```

**Issue: Authentication failed**
```bash
# Verify token has correct permissions
ssh root@proxmox "pveum user list"
ssh root@proxmox "pveum acl list"
```

### Ansible Issues

**Issue: Host unreachable**
```bash
# Test connectivity
ansible all -i inventory/production.yml -m ping

# Check firewall on VMs
ssh sysadmin@10.9.11.20 "sudo ufw status"
```

**Issue: Permission denied**
```bash
# Verify SSH key
ssh -i ~/.ssh/id_ed25519 sysadmin@10.9.11.20

# Check ansible_ssh_private_key_file in inventory
```

**Issue: Playbook fails on specific task**
```bash
# Run in verbose mode
ansible-playbook -i inventory/production.yml playbook.yaml -vvv

# Run in check mode (dry-run)
ansible-playbook -i inventory/production.yml playbook.yaml --check
```

## Security Best Practices

1. **Never commit secrets:**
   - `.tfvars` files are gitignored
   - `.pkrvars.hcl` files are gitignored
   - Use environment variables or vaults for tokens

2. **Rotate API tokens regularly:**
   ```bash
   # Create new token
   pveum user token add packer@pve packer-token-2

   # Update in .pkrvars.hcl
   # Delete old token
   pveum user token remove packer@pve packer-token
   ```

3. **Use separate tokens per environment:**
   - Different tokens for staging vs production
   - Separate permissions for read-only operations

4. **SSH key management:**
   - Use ED25519 keys (stronger than RSA)
   - Different keys for different environments
   - Rotate keys periodically

5. **Network isolation:**
   - Templates on management VLAN
   - Production VMs on isolated VLANs
   - Bastion host for access

## Advanced Topics

### Using Terraform Workspaces

```bash
# Create staging workspace
terraform workspace new staging

# Create production workspace
terraform workspace new production

# Switch between workspaces
terraform workspace select staging
terraform apply

terraform workspace select production
terraform apply
```

### Integrating with CI/CD

```yaml
# .github/workflows/deploy.yml
name: Deploy Infrastructure

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: self-hosted  # Bastion host
    steps:
      - uses: actions/checkout@v3

      - name: Terraform Apply
        run: |
          cd hardened-linux/terraform
          terraform init
          terraform apply -auto-approve

      - name: Run Ansible
        run: |
          cd hardened-linux
          ansible-playbook -i inventory/production.yml playbook.yaml
```

### Using Ansible Vault for Secrets

```bash
# Encrypt sensitive variables
ansible-vault create inventory/secrets.yml

# Edit encrypted file
ansible-vault edit inventory/secrets.yml

# Run playbook with vault
ansible-playbook -i inventory/production.yml playbook.yaml --ask-vault-pass
```

## Resources

- [Packer Documentation](https://www.packer.io/docs)
- [Terraform Proxmox Provider](https://registry.terraform.io/providers/Telmate/proxmox/latest/docs)
- [Ansible Documentation](https://docs.ansible.com/)
- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)

## Support

For issues or questions:

1. Check the troubleshooting section above
2. Review Packer/Terraform/Ansible logs with `-v` flags
3. Check Proxmox task logs in web UI
4. Verify network connectivity and permissions
