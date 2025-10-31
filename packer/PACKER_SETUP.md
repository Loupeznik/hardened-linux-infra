# Packer Installation and Setup Guide

This guide covers installing and configuring HashiCorp Packer for building VM templates on Proxmox and ESXi.

## Table of Contents

- [What is Packer?](#what-is-packer)
- [Installation](#installation)
  - [Linux (Debian/Ubuntu)](#linux-debianubuntu)
  - [Linux (RHEL/AlmaLinux/Fedora)](#linux-rhelalmalinuxfedora)
  - [macOS](#macos)
  - [Windows](#windows)
- [Verifying Installation](#verifying-installation)
- [Proxmox Prerequisites](#proxmox-prerequisites)
- [ESXi Prerequisites](#esxi-prerequisites)
- [Configuration](#configuration)
- [Building Your First Template](#building-your-first-template)
- [Troubleshooting](#troubleshooting)

## What is Packer?

**Packer** is an open-source tool by HashiCorp that automates the creation of machine images across multiple platforms (Proxmox, VMware, AWS, Azure, etc.). It allows you to:

- Define infrastructure as code using HCL (HashiCorp Configuration Language)
- Build identical machine images for multiple platforms from a single source configuration
- Automate OS installation, partitioning, and initial configuration
- Create reproducible, versioned VM templates

### Important: Where to Run Packer

**CRITICAL:** Packer must be run from a machine that the Proxmox VMs can reach over the network. During the build process, Packer starts an HTTP server to serve cloud-init/kickstart configurations to the installing VM.

**Valid options:**
- **Recommended:** A bastion/jumphost VM within the Proxmox environment (on the same network as your VMs)
- The Proxmox host itself (not recommended for production due to security)
- A machine on the same network/VLAN as the Proxmox VMs

**Will NOT work:**
- Your local laptop/desktop if it's on a different network without proper routing
- Machines behind NAT that VMs cannot reach
- Remote machines without a public IP or VPN access to the Proxmox network

### Why Use Packer?

Instead of manually:
1. Mounting ISO
2. Clicking through installation wizard
3. Partitioning disks
4. Configuring network
5. Installing packages
6. Cleaning up

Packer does all of this automatically and reproducibly with a single command.

## Installation

### Linux (Debian/Ubuntu)

```bash
# Add HashiCorp GPG key
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# Add HashiCorp repository
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# Update and install
sudo apt update
sudo apt install packer
```

### Linux (RHEL/AlmaLinux/Fedora)

```bash
# Add HashiCorp repository
sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/fedora/hashicorp.repo

# Install Packer
sudo dnf install packer
```

### macOS

**Option 1: Homebrew (Recommended)**

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/packer
```

**Option 2: Manual Download**

1. Download from https://www.packer.io/downloads
2. Unzip the package
3. Move to `/usr/local/bin`:
   ```bash
   sudo mv packer /usr/local/bin/
   ```

### Windows

**Option 1: Chocolatey**

```powershell
choco install packer
```

**Option 2: Manual Download**

1. Download from https://www.packer.io/downloads
2. Extract the ZIP file
3. Add the directory to your `PATH` environment variable

## Verifying Installation

After installation, verify Packer is working:

```bash
packer version
```

Expected output:
```
Packer v1.11.2
```

## Proxmox Prerequisites

### 1. Verify Node Hostname

**IMPORTANT:** Ensure your Proxmox node hostname is properly configured in `/etc/hosts`. Packer requires the node to resolve its own hostname.

```bash
# Check your Proxmox hostname
hostname

# Verify /etc/hosts contains the hostname mapping
cat /etc/hosts
```

Your `/etc/hosts` should contain an entry like:
```
127.0.0.1 localhost
<your-ip> <hostname>.domain.com <hostname>
```

**Example:**
```
65.109.98.48 pve-prod-02.dzarsky.eu pve-prod-02
```

**Note the actual hostname** (e.g., `pve-prod-02`) - you'll need this for the `proxmox_node` variable in your Packer configuration, **NOT** the default `pve`.

### 2. Create API Token

Packer needs API access to Proxmox. Create a dedicated user and token:

```bash
# SSH into your Proxmox host

# Create a new user for Packer
pveum user add packer@pve --comment "Packer automation user"

# Create an API token
pveum user token add packer@pve packer-token --privsep=0

# Note the token ID and secret - you'll need these!
# Example output:
# ┌──────────────┬──────────────────────────────────────┐
# │ key          │ value                                │
# ╞══════════════╪══════════════════════════════════════╡
# │ full-tokenid │ packer@pve!packer-token              │
# ├──────────────┼──────────────────────────────────────┤
# │ info         │ {"privsep":0}                        │
# ├──────────────┼──────────────────────────────────────┤
# │ value        │ xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx │
# └──────────────┴──────────────────────────────────────┘

# Grant necessary permissions
pveum acl modify / --user packer@pve --role PVEVMAdmin
pveum acl modify /storage --user packer@pve --role PVEDatastoreUser

# If using Proxmox SDN (Software Defined Networking), grant SDN permissions
# This is REQUIRED if your network bridge is a vnet (e.g., vnet0)
pveum acl modify /sdn --user packer@pve --role PVESDNUser
```

**Save the token secret securely** - it won't be shown again!

### 3. Verify Storage Pools

Check your Proxmox storage pools:

```bash
pvesm status
```

Note the storage pool names (e.g., `local`, `local-lvm`, `storage`) - you'll need these in Packer configuration.

### 4. Upload ISOs (REQUIRED)

**IMPORTANT:** The Packer configurations in this repository require ISOs to be pre-uploaded to Proxmox. Automatic ISO download/upload is disabled due to potential timeout issues with large ISO files.

#### Why Pre-upload ISOs?

During testing, we encountered two issues with automatic ISO handling:
1. **Upload timeout**: Large ISOs (3GB+) can timeout when uploading through Proxmox API
2. **Download restrictions**: Proxmox servers may not have direct internet access or may be behind firewalls

#### Upload Methods

**Option A: Via Proxmox Web UI (Easiest)**

1. Download the ISO to your local machine first
2. Open Proxmox web interface (https://your-proxmox:8006)
3. Navigate to: **Datacenter → [node-name] → local (or your ISO storage) → ISO Images**
4. Click **Upload** button
5. Select and upload the ISO file

**Option B: Via Command Line**

```bash
# SSH into your Proxmox host
cd /var/lib/vz/template/iso

# Download Ubuntu 24.04.3 LTS (current stable)
wget https://releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso

# Download AlmaLinux 10 (latest)
wget https://repo.almalinux.org/almalinux/10/isos/x86_64/AlmaLinux-10-latest-x86_64-boot.iso

# Verify checksums
wget https://releases.ubuntu.com/24.04/SHA256SUMS
sha256sum -c SHA256SUMS 2>&1 | grep ubuntu-24.04.3-live-server-amd64.iso
```

**Option C: Upload from Local Machine**

```bash
# From your local machine with ISO already downloaded
scp ubuntu-24.04.3-live-server-amd64.iso root@proxmox-host:/var/lib/vz/template/iso/
scp AlmaLinux-10-latest-x86_64-boot.iso root@proxmox-host:/var/lib/vz/template/iso/
```

#### Verify ISO Upload

```bash
# On Proxmox host
pvesm list local --content iso

# Or check the directory directly
ls -lh /var/lib/vz/template/iso/
```

#### Current ISO Versions

As of this writing, the Packer templates use:

- **Ubuntu**: `ubuntu-24.04.3-live-server-amd64.iso`
  - SHA256: `c3514bf0056180d09376462a7a1b4f213c1d6e8ea67fae5c25099c6fd3d8274b`
  - URL: https://releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso

- **AlmaLinux**: `AlmaLinux-10-latest-x86_64-dvd.iso` (use DVD, not boot ISO)
  - URL: https://repo.almalinux.org/almalinux/10/isos/x86_64/AlmaLinux-10-latest-x86_64-dvd.iso
  - Note: The boot ISO requires network installation and may not work in all environments. Use the full DVD ISO.

**Note:** Update the ISO filename in your `*.pkrvars.hcl` file if using a different version.

## ESXi Prerequisites

### 1. Enable SSH

1. Log into ESXi web UI
2. Navigate to **Host** → **Actions** → **Services** → **Enable Secure Shell (SSH)**

### 2. Enable GuestIPHack

Required for Packer to detect IP addresses:

```bash
# SSH into ESXi host
esxcli system settings advanced set -o /Net/GuestIPHack -i 1
```

### 3. Create Datastore

Ensure you have a datastore where Packer can create VMs.

**Note:** The Packer Proxmox plugin is more mature than ESXi. For ESXi, consider using the `vsphere-iso` builder.

## Configuration

### Project Structure

The Packer templates in this repository are organized as follows:

```
packer/
├── ubuntu/
│   └── ubuntu-24.04.pkr.hcl          # Ubuntu Packer template
├── almalinux/
│   └── almalinux-10.pkr.hcl          # AlmaLinux Packer template
├── cloud-init/
│   ├── ubuntu/
│   │   ├── user-data                 # Ubuntu cloud-init config
│   │   └── meta-data                 # Ubuntu metadata
│   └── almalinux/
│       ├── user-data                 # AlmaLinux cloud-init config
│       ├── meta-data                 # AlmaLinux metadata
│       └── kickstart.cfg             # AlmaLinux kickstart file
└── variables/
    ├── ubuntu.pkrvars.hcl            # Ubuntu variables (you'll create this)
    └── almalinux.pkrvars.hcl         # AlmaLinux variables (you'll create this)
```

### Create Variables File

Create a variables file for your environment. Do **not** commit this file to version control as it contains sensitive information.

**For Ubuntu:**

Create `packer/variables/ubuntu.pkrvars.hcl`:

```hcl
# Proxmox connection
proxmox_url      = "https://proxmox.example.com:8006/api2/json"
proxmox_username = "packer@pve!packer-token"
proxmox_token    = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
proxmox_node     = "pve-prod-02"  # Use your actual Proxmox node hostname, NOT "pve"

# Storage
proxmox_storage_pool = "local-lvm"
proxmox_iso_storage  = "local"

# VM template configuration
vm_id   = 9000
vm_name = "ubuntu-24.04-hardened-template"

# Resources
vm_cpu_cores = 2
vm_memory    = 4096
vm_disk_size = "80G"

# Network configuration for template build
vm_network_bridge = "vmbr0"
vm_ip_address     = "10.0.1.100"
vm_network_prefix = 24
vm_gateway        = "10.0.1.1"
vm_dns_primary    = "8.8.8.8"
vm_dns_secondary  = "8.8.4.4"
vm_dns_domain     = "example.com"

# Credentials (temporary, only for template build)
vm_hostname       = "ubuntu-template"
vm_admin_user     = "sysadmin"
vm_admin_password = "ChangeMe123!TempPassword"
vm_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExample... your-key@example.com"

# System settings
vm_timezone = "America/New_York"
```

**For AlmaLinux:**

Create `packer/variables/almalinux.pkrvars.hcl`:

```hcl
# Proxmox connection
proxmox_url      = "https://proxmox.example.com:8006/api2/json"
proxmox_username = "packer@pve!packer-token"
proxmox_token    = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
proxmox_node     = "pve-prod-02"  # Use your actual Proxmox node hostname, NOT "pve"

# Storage
proxmox_storage_pool = "local-lvm"
proxmox_iso_storage  = "local"

# VM template configuration
vm_id   = 9001
vm_name = "almalinux-10-hardened-template"

# Resources
vm_cpu_cores = 2
vm_memory    = 4096
vm_disk_size = "80G"

# Network configuration for template build
vm_network_bridge = "vmbr0"
vm_ip_address     = "10.0.1.101"
vm_network_prefix = 24
vm_gateway        = "10.0.1.1"
vm_dns_primary    = "8.8.8.8"
vm_dns_secondary  = "8.8.4.4"
vm_dns_domain     = "example.com"

# Credentials (temporary, only for template build)
vm_hostname       = "almalinux-template"
vm_admin_user     = "sysadmin"
vm_admin_password = "ChangeMe123!TempPassword"
vm_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExample... your-key@example.com"

# System settings
vm_timezone = "America/New_York"
```

### Generate SSH Key (if needed)

If you don't have an SSH key yet:

```bash
# Generate ED25519 key (recommended)
ssh-keygen -t ed25519 -C "packer-automation@example.com" -f ~/.ssh/packer_ed25519

# Copy the public key
cat ~/.ssh/packer_ed25519.pub
```

Paste the public key into the `vm_ssh_public_key` variable in your `.pkrvars.hcl` file.

### .gitignore Configuration

Add to your `.gitignore`:

```gitignore
# Packer
*.pkrvars.hcl
packer/variables/
.packer.d/
packer_cache/
crash.log
```

## Building Your First Template

### Step 1: Initialize Packer

Navigate to the Packer template directory and initialize:

```bash
cd hardened-linux/packer/ubuntu
packer init ubuntu-24.04.pkr.hcl
```

This downloads required plugins (like the Proxmox plugin).

### Step 2: Validate Configuration

Check for syntax errors:

```bash
packer validate -var-file=../variables/ubuntu.pkrvars.hcl ubuntu-24.04.pkr.hcl
```

Expected output:
```
The configuration is valid.
```

### Step 3: Build the Template

Build the template:

```bash
packer build -var-file=../variables/ubuntu.pkrvars.hcl ubuntu-24.04.pkr.hcl
```

**What happens during build:**

1. Packer creates a VM in Proxmox
2. Mounts the ISO
3. Boots the VM
4. Sends boot commands to start automated installation
5. Serves cloud-init/kickstart config via HTTP
6. Waits for OS installation to complete
7. Connects via SSH
8. Runs provisioning scripts
9. Cleans up logs and history
10. Converts VM to template

Build time: **10-20 minutes** depending on your hardware and network.

### Step 4: Verify Template

Check Proxmox web UI - you should see a new template with ID `9000` (or `9001` for AlmaLinux).

## Building AlmaLinux Template

Same process for AlmaLinux:

```bash
cd ansible/playbooks/hardened-linux/packer/almalinux
packer init almalinux-10.pkr.hcl
packer validate -var-file=../variables/almalinux.pkrvars.hcl almalinux-10.pkr.hcl
packer build -var-file=../variables/almalinux.pkrvars.hcl almalinux-10.pkr.hcl
```

## Advanced Usage

### Debug Mode

If build fails, enable debug mode for detailed output:

```bash
PACKER_LOG=1 packer build -var-file=../variables/ubuntu.pkrvars.hcl ubuntu-24.04.pkr.hcl
```

### Force Rebuild

If template already exists:

```bash
packer build -force -var-file=../variables/ubuntu.pkrvars.hcl ubuntu-24.04.pkr.hcl
```

### Build Only Specific Steps

```bash
# Show available build targets
packer build -machine-readable ubuntu-24.04.pkr.hcl | grep 'artifact,'

# Build only specific provisioner
packer build -on-error=ask -var-file=../variables/ubuntu.pkrvars.hcl ubuntu-24.04.pkr.hcl
```

### Parallel Builds

Build both templates simultaneously:

```bash
# Terminal 1
cd packer/ubuntu
packer build -var-file=../variables/ubuntu.pkrvars.hcl ubuntu-24.04.pkr.hcl

# Terminal 2
cd packer/almalinux
packer build -var-file=../variables/almalinux.pkrvars.hcl almalinux-10.pkr.hcl
```

## Using the Template

### Clone from Template

Once template is built, clone it in Proxmox:

**Via Web UI:**
1. Right-click template → Clone
2. Choose Full Clone
3. Set VM ID and name
4. Start the VM

**Via CLI:**

```bash
# Clone template
qm clone 9000 100 --name web-server-01 --full

# Customize cloud-init settings
qm set 100 --ipconfig0 ip=10.0.1.10/24,gw=10.0.1.1
qm set 100 --sshkeys ~/.ssh/authorized_keys

# Start VM
qm start 100
```

### With Terraform

Create VMs from template using Terraform:

```hcl
resource "proxmox_vm_qemu" "web_server" {
  name        = "web-server-01"
  target_node = "pve"
  clone       = "ubuntu-24.04-hardened-template"

  cores   = 4
  memory  = 8192

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  ipconfig0 = "ip=10.0.1.10/24,gw=10.0.1.1"
  sshkeys   = file("~/.ssh/id_ed25519.pub")
}
```

## Troubleshooting

### Issue: "hostname lookup 'pve' failed - Name or service not known"

**Cause:** Proxmox node cannot resolve its own hostname, or you're using the wrong node name in `proxmox_node` variable

**Solution:**
```bash
# On Proxmox host, check actual hostname
hostname

# Verify /etc/hosts contains proper mapping
cat /etc/hosts

# Update your variables file with the correct node name
# Example: proxmox_node = "pve-prod-02" (NOT "pve")
```

### Issue: "Permission check failed (/sdn/zones/..., SDN.Use)"

**Cause:** The packer user lacks permission to use Proxmox SDN (Software Defined Networking) resources

**Solution:**
```bash
# Grant SDN permissions to packer user
pveum acl modify /sdn --user packer@pve --role PVESDNUser

# Or grant on specific zone/vnet
pveum acl modify /sdn/zones/your-zone --user packer@pve --role PVESDNUser
```

### Issue: "Failed to connect to Proxmox API"

**Cause:** Invalid credentials or URL

**Solution:**
```bash
# Test API access manually
curl -k https://proxmox.example.com:8006/api2/json/access/ticket \
  -d "username=packer@pve!packer-token" \
  -d "password=your-token-secret"
```

### Issue: "ISO not found" or "failed to download ISO"

**Cause:** ISO not uploaded to Proxmox storage

**Solution:**
```bash
# Check ISO storage
pvesm list local --content iso

# Upload ISO manually (see section "Upload ISOs (REQUIRED)")
cd /var/lib/vz/template/iso
wget https://releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso
```

### Issue: "Error uploading ISO: write tcp ... use of closed network connection"

**Cause:** ISO upload timeout through Proxmox API (large ISOs 3GB+ can timeout)

**Solution:** Pre-upload ISOs directly to Proxmox using one of the methods in the "Upload ISOs (REQUIRED)" section. The Packer templates are configured to reference pre-uploaded ISOs to avoid this issue.

### Issue: "Boot command timeout"

**Cause:** Boot commands don't match installation media

**Solution:**
- Verify ISO URL and checksum
- Check boot command timing in `.pkr.hcl`
- Try increasing `boot_wait`

### Issue: "SSH timeout"

**Cause:** Network misconfiguration or SSH not enabled

**Solution:**
- Verify IP address, gateway, DNS in variables
- Check cloud-init/kickstart config
- Ensure `vm_ip_address` is available on network
- Check firewall rules

### Issue: "Permission denied during build"

**Cause:** Insufficient Proxmox permissions

**Solution:**
```bash
# Grant additional permissions
pveum acl modify / --user packer@pve --role Administrator
```

### Issue: "Template already exists"

**Cause:** Template with same ID exists

**Solution:**
```bash
# Delete existing template
qm destroy 9000

# Or use -force flag
packer build -force -var-file=../variables/ubuntu.pkrvars.hcl ubuntu-24.04.pkr.hcl
```

## Best Practices

1. **Version Control**: Track Packer configurations in git, but exclude `.pkrvars.hcl` files
2. **Secrets Management**: Use environment variables or HashiCorp Vault for sensitive data
3. **Template Versioning**: Include date/version in template names
4. **Testing**: Test templates in dev environment before production
5. **Documentation**: Document customizations and special configurations
6. **Regular Updates**: Rebuild templates monthly to include security patches
7. **Backup**: Export working templates as backup

## Next Steps

After building templates:

1. **Test the template** by cloning and booting a VM
2. **Run Ansible playbooks** from [../../](../../README.md) to apply hardening
3. **Create Terraform modules** to deploy VMs from templates
4. **Set up CI/CD** to rebuild templates automatically

## Resources

- [Packer Documentation](https://www.packer.io/docs)
- [Packer Proxmox Builder](https://www.packer.io/plugins/builders/proxmox/iso)
- [Cloud-init Documentation](https://cloudinit.readthedocs.io/)
- [AlmaLinux Kickstart Guide](https://docs.almalinux.org/documentation/installation-guide.html)

## Support

If you encounter issues:

1. Check Packer logs: `PACKER_LOG=1 packer build ...`
2. Review Proxmox task log in web UI
3. Check cloud-init logs in VM: `/var/log/cloud-init.log`
4. Verify network connectivity and DNS resolution
