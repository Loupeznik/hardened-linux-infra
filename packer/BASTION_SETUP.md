# Bastion VM Setup for Packer

This guide explains how to set up a bastion/jumphost VM in Proxmox to run Packer and Ansible automation tasks.

## Why a Bastion VM?

A bastion VM serves as a dedicated automation host within your Proxmox environment:

- **Network accessibility**: VMs can reach the bastion to fetch cloud-init configs during Packer builds
- **Isolation**: Keep automation tools separate from the Proxmox host
- **Security**: Single point of access for infrastructure automation
- **Consistency**: Reproducible environment for running automation tasks

## Prerequisites

- Proxmox access
- SSH key for authentication
- Network connectivity to Proxmox

## Step 1: Create the Bastion VM

### Option A: Manual Creation via Proxmox UI

1. **Download Ubuntu Server ISO**
   ```bash
   # On Proxmox host
   cd /var/lib/vz/template/iso
   wget https://releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso
   ```

2. **Create VM in Proxmox UI**
   - Click "Create VM"
   - **General:**
     - VM ID: 100 (or your choice)
     - Name: `bastion-01`
   - **OS:**
     - ISO: ubuntu-24.04.3-live-server-amd64.iso
   - **System:**
     - QEMU Agent: Enabled
   - **Disks:**
     - Size: 32GB minimum
     - Storage: your preferred storage pool
   - **CPU:**
     - Cores: 2
   - **Memory:**
     - 4096 MB (4GB)
   - **Network:**
     - Bridge: vnet0 (or your management network)
     - Model: VirtIO

3. **Install Ubuntu**
   - Start the VM and access console
   - Follow Ubuntu installer:
     - Hostname: `bastion-01`
     - Username: `automation` (or your choice)
     - Enable SSH server
     - Install OpenSSH server
   - Complete installation and reboot

### Option B: Via Proxmox CLI

```bash
# On Proxmox host
qm create 100 \
  --name bastion-01 \
  --memory 4096 \
  --cores 2 \
  --net0 virtio,bridge=vnet0 \
  --scsi0 storage:32 \
  --ide2 local:iso/ubuntu-24.04.3-live-server-amd64.iso,media=cdrom \
  --boot order=scsi0 \
  --agent enabled=1 \
  --ostype l26

# Start VM and complete installation via console
qm start 100
```

## Step 2: Configure Network

After installation, configure static IP for the bastion:

```bash
# SSH into the bastion VM
ssh automation@<bastion-ip>

# Edit netplan configuration
sudo nano /etc/netplan/50-cloud-init.yaml
```

Example configuration:
```yaml
network:
  version: 2
  ethernets:
    ens18:
      dhcp4: false
      addresses:
        - 10.9.11.10/24
      routes:
        - to: default
          via: 10.9.11.0
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
```

Apply the configuration:
```bash
sudo netplan apply
```

**Important:** Choose an IP address in the same network as your Proxmox VMs (e.g., if VMs use 10.9.11.x, put bastion on 10.9.11.10).

## Step 3: Install Required Tools

### Install Packer

```bash
# Add HashiCorp repository
wget -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list

# Install Packer
sudo apt update
sudo apt install -y packer
```

### Install Ansible

```bash
sudo apt update
sudo apt install -y ansible python3-pip git curl wget vim tmux
```

### Verify Installations

```bash
packer version
ansible --version
git --version
```

## Step 4: Configure SSH Access

### Generate SSH Key (if not already done)

```bash
# On your local machine
ssh-keygen -t ed25519 -C "automation@bastion" -f ~/.ssh/bastion_ed25519
```

### Copy SSH Key to Bastion

```bash
# From your local machine
ssh-copy-id -i ~/.ssh/bastion_ed25519.pub automation@10.9.11.10
```

### Configure SSH Config

Add to your `~/.ssh/config` on your local machine:

```
Host bastion
    HostName 10.9.11.10
    User automation
    IdentityFile ~/.ssh/bastion_ed25519
    ForwardAgent yes
```

Now you can connect with: `ssh bastion`

## Step 5: Set Up Project Directory

```bash
# SSH into bastion
ssh bastion

# Create project directory
mkdir -p ~/automation
cd ~/automation

# Clone your repository
git clone https://github.com/loupeznik/playbooks.git
cd playbooks/hardened-linux/packer
```

## Step 6: Configure Packer Variables

Create your Packer variables file:

```bash
mkdir -p variables
nano variables/ubuntu.pkrvars.hcl
```

Example configuration:
```hcl
# Proxmox Connection Settings
proxmox_url      = "https://65.109.98.48:8006/api2/json"
proxmox_username = "packer@pve!packer-token"
proxmox_token    = "your-token-here"
proxmox_node     = "pve-prod-02"

# Storage Configuration
proxmox_storage_pool = "storage"
proxmox_iso_storage  = "local"

# VM Template Configuration
vm_id   = 9000
vm_name = "ubuntu-24.04-hardened-template"

# VM Resources
vm_cpu_cores = 2
vm_cpu_type  = "host"
vm_memory    = 4096
vm_disk_size = "30G"
vm_disk_type = "scsi"

# Network Configuration
# IMPORTANT: Use the bastion's network settings
vm_network_bridge = "vnet0"
vm_network_model  = "virtio"
vm_ip_address     = "10.9.11.80"  # Choose available IP in same network
vm_network_prefix = 24
vm_gateway        = "10.9.11.0"
vm_dns_primary    = "8.8.8.8"
vm_dns_secondary  = "8.8.4.4"
vm_dns_domain     = "dzarsky.eu"

# VM Configuration (temporary)
vm_hostname       = "ubuntu-template"
vm_admin_user     = "sysadmin"
vm_admin_password = "SecurePassword123!"
vm_ssh_public_key = "ssh-ed25519 AAAAC3... your-key"

# System Settings
vm_timezone = "Europe/Prague"
```

## Step 7: Test Packer Build

```bash
# Initialize Packer
cd ~/automation/playbooks/hardened-linux/packer/ubuntu
packer init ubuntu-24.04.pkr.hcl

# Validate configuration
packer validate -var-file=../variables/ubuntu.pkrvars.hcl ubuntu-24.04.pkr.hcl

# Run build
packer build -var-file=../variables/ubuntu.pkrvars.hcl ubuntu-24.04.pkr.hcl
```

## Step 8: Firewall Configuration (Optional)

If you have a firewall on the bastion, allow Packer's HTTP server:

```bash
# Allow ephemeral ports for Packer HTTP server
sudo ufw allow from 10.9.11.0/24 to any port 8000:9000 proto tcp comment 'Packer HTTP Server'

# Or if using specific port range
sudo ufw allow 8553/tcp comment 'Packer HTTP Server'
```

## Security Considerations

### Hardening the Bastion

1. **Disable password authentication**
   ```bash
   sudo nano /etc/ssh/sshd_config
   # Set: PasswordAuthentication no
   sudo systemctl restart sshd
   ```

2. **Enable automatic security updates**
   ```bash
   sudo apt install -y unattended-upgrades
   sudo dpkg-reconfigure -plow unattended-upgrades
   ```

3. **Configure firewall**
   ```bash
   sudo ufw default deny incoming
   sudo ufw default allow outgoing
   sudo ufw allow ssh
   sudo ufw enable
   ```

4. **Install fail2ban**
   ```bash
   sudo apt install -y fail2ban
   sudo systemctl enable fail2ban
   ```

### API Token Security

- Store Proxmox API token in `~/.packer_token` with restricted permissions
- Never commit `.pkrvars.hcl` files to git
- Use environment variables for sensitive data where possible

```bash
# Store token securely
echo "your-token-here" > ~/.packer_token
chmod 600 ~/.packer_token

# Reference in scripts
export PROXMOX_TOKEN=$(cat ~/.packer_token)
```

## Using the Bastion for Ansible

The bastion can also run Ansible playbooks:

```bash
# Install Ansible collections
ansible-galaxy collection install community.general

# Run playbooks against Proxmox VMs
cd ~/automation/playbooks
ansible-playbook -i inventories/production.yaml debian_based/basic-server-setup.yaml
```

## Maintenance

### Update the Bastion

```bash
# Regular updates
sudo apt update
sudo apt upgrade -y

# Update Packer
sudo apt update && sudo apt upgrade packer

# Update Ansible
pip3 install --upgrade ansible
```

### Backup Configuration

```bash
# Backup important files
tar -czf ~/bastion-backup-$(date +%F).tar.gz \
  ~/automation \
  ~/.ssh \
  ~/.packer_token \
  /etc/netplan
```

## Troubleshooting

### Cannot Reach Proxmox API

```bash
# Test connectivity
curl -k https://65.109.98.48:8006/api2/json/version

# Check routes
ip route show
```

### Packer HTTP Server Not Reachable

```bash
# Verify bastion IP is correct
ip addr show

# Test if VMs can reach bastion (from Proxmox host)
ping 10.9.11.10

# Check if HTTP server is listening
netstat -tlnp | grep packer
```

### SSH Connection Issues

```bash
# Test SSH from bastion to Proxmox
ssh root@65.109.98.48

# Verify SSH key permissions
chmod 600 ~/.ssh/bastion_ed25519
```

## Next Steps

- Set up Git hooks for automated deployments
- Configure CI/CD pipelines to run from bastion
- Create additional automation scripts
- Set up monitoring for the bastion VM

## Resources

- [PACKER_SETUP.md](PACKER_SETUP.md) - Packer installation and configuration
- [Proxmox Documentation](https://pve.proxmox.com/wiki/Main_Page)
- [Packer Documentation](https://www.packer.io/docs)
