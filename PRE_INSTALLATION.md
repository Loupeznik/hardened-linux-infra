# Pre-Installation Guide

This guide walks through the complete process of preparing servers for hardening with Ansible playbooks, from initial OS installation to first playbook run.

## Table of Contents

- [Planning Phase](#planning-phase)
- [Server Installation](#server-installation)
  - [Ubuntu 24.04 LTS Installation](#ubuntu-2204-lts-installation)
  - [AlmaLinux 10.x Installation](#almalinux-9x-installation)
- [Post-Installation Configuration](#post-installation-configuration)
- [Ansible Control Node Setup](#ansible-control-node-setup)
- [Pre-Flight Checklist](#pre-flight-checklist)

## Planning Phase

Before installing servers, plan the following:

### 1. Network Configuration

Document for each server:

| Server | Hostname | IP Address | Gateway | DNS | VLAN/Subnet |
|--------|----------|------------|---------|-----|-------------|
| app01 | app01.example.com | 10.0.1.10 | 10.0.1.1 | 10.0.0.53 | App Subnet |
| db01 | db01.example.com | 10.0.2.10 | 10.0.2.1 | 10.0.0.53 | DB Subnet |
| build01 | build01.example.com | 10.0.3.10 | 10.0.3.1 | 10.0.0.53 | Build Subnet |

### 2. Server Specifications

**Minimum Requirements:**

| Server Type | CPU | RAM | Disk | Notes |
|-------------|-----|-----|------|-------|
| App Server | 2 cores | 4GB | 40GB | +storage for containers |
| DB Server | 4 cores | 8GB | 100GB | +dedicated data disk |
| Build Server | 4 cores | 8GB | 100GB | +ephemeral build space |

**Recommended:**

| Server Type | CPU | RAM | Disk | Notes |
|-------------|-----|-----|------|-------|
| App Server | 4 cores | 8GB | 100GB | SSD for containers |
| DB Server | 8 cores | 16GB | 200GB | NVMe for data |
| Build Server | 8 cores | 16GB | 200GB | SSD for fast builds |

### 3. Disk Partitioning Plan

**Standard Layout:**

```
/boot       1GB    ext4
/           20GB   ext4
/tmp        5GB    ext4 (nodev,nosuid,noexec)
/var        20GB   ext4 (nodev)
/var/log    10GB   ext4 (nodev,nosuid,noexec)
/home       10GB   ext4 (nodev,nosuid)
swap        2-4GB  swap
```

**Database Server Additional:**

```
/var/lib/postgresql  100GB+  ext4 (nodev)  - on separate disk if possible
```

**Build Server Additional:**

```
/var/lib/docker     50GB+   ext4 (nodev)   - fast SSD recommended
/home/runner/work   50GB+   ext4 (nodev)   - ephemeral build space
```

### 4. User Accounts

Plan the following user accounts:

- **Admin user**: `sysadmin` (will be created during OS installation)
- **Service users**: Created by playbooks
  - App server: `appuser`, `www-data`/`nginx`
  - DB server: `postgres`
  - Build server: `runner`

### 5. SSH Keys

Generate SSH keys on the Ansible control node:

```bash
# Generate ED25519 key (recommended)
ssh-keygen -t ed25519 -C "ansible-control@yourdomain.com" -f ~/.ssh/ansible_ed25519

# Or RSA if ED25519 not supported
ssh-keygen -t rsa -b 4096 -C "ansible-control@yourdomain.com" -f ~/.ssh/ansible_rsa
```

**Important:** Store the private key securely and never commit to version control.

## Server Installation

### Ubuntu 24.04 LTS Installation

#### Step 1: Download ISO

Download Ubuntu Server 22.04 LTS:
- URL: https://ubuntu.com/download/server
- Verify checksum after download

```bash
# Verify ISO checksum
sha256sum ubuntu-24.04.x-live-server-amd64.iso
```

#### Step 2: Boot from Installation Media

1. Boot server from ISO (USB/CD/virtual media)
2. Select language: **English**
3. Select **Install Ubuntu Server**

#### Step 3: Network Configuration

1. Select network interface
2. Choose **Manual** network configuration
3. Enter network details:
   ```
   IPv4 Method: Manual
   Subnet: 10.0.1.0/24
   Address: 10.0.1.10
   Gateway: 10.0.1.1
   Name servers: 10.0.0.53,8.8.8.8
   Search domains: example.com
   ```
4. Test connectivity, then continue

#### Step 4: Storage Configuration

**Option A: Guided - Use Entire Disk (Simple)**

1. Select **Use an entire disk**
2. Choose target disk
3. **Deselect** "Set up this disk as an LVM group" (for simplicity)
4. Review layout and continue

**Option B: Manual (Recommended for Production)**

1. Select **Custom storage layout**
2. Create partitions according to plan:

```bash
# Example partition scheme
/dev/sda1  1GB    /boot      ext4
/dev/sda2  20GB   /          ext4
/dev/sda3  5GB    /tmp       ext4
/dev/sda4  20GB   /var       ext4
/dev/sda5  10GB   /var/log   ext4
/dev/sda6  10GB   /home      ext4
/dev/sda7  4GB    swap       swap
```

3. For database servers, create additional partition:
```bash
/dev/sdb1  100GB  /var/lib/postgresql  ext4
```

4. Review and confirm

#### Step 5: Profile Setup

Enter system information:

```
Your name: System Administrator
Your server's name: app01
Pick a username: sysadmin
Choose a password: [Strong password - will be disabled after SSH key setup]
Confirm password: [Same password]
```

**Important:**
- Use a strong password initially
- Playbooks will enforce SSH-key-only authentication later
- Username should match what you'll use in Ansible inventory

#### Step 6: SSH Setup

1. **Install OpenSSH server**: ✓ (checked)
2. **Import SSH identity**: Select **from GitHub** or **from Launchpad** if you have keys there
   - OR skip and manually add later

#### Step 7: Featured Server Snaps

**Deselect all** - playbooks will install required software

#### Step 8: Complete Installation

1. Installation proceeds (5-10 minutes)
2. When complete: **Reboot Now**
3. Remove installation media
4. Server boots to login prompt

#### Step 9: First Login (Ubuntu)

```bash
# Login with created user
login: sysadmin
password: [your password]

# Update system
sudo apt update && sudo apt upgrade -y

# Set timezone
sudo timedatectl set-timezone America/New_York  # Adjust as needed

# Verify network
ip addr show
ping -c 3 8.8.8.8

# Check hostname
hostnamectl

# If hostname incorrect:
sudo hostnamectl set-hostname app01.example.com
```

### AlmaLinux 10.x Installation

#### Step 1: Download ISO

Download AlmaLinux 10.x:
- URL: https://almalinux.org/get-almalinux/
- Choose: **AlmaLinux-10.x-x86_64-minimal.iso**
- Verify checksum

```bash
sha256sum AlmaLinux-10.x-x86_64-minimal.iso
```

#### Step 2: Boot and Initial Setup

1. Boot from ISO
2. Select **Install AlmaLinux 10**
3. Select language: **English (United States)**
4. Click **Continue**

#### Step 3: Installation Summary Screen

Configure the following sections:

##### Network & Hostname

1. Click **Network & Host Name**
2. Set hostname: `app02.example.com`
3. Select network interface
4. Click **Configure**
5. Go to **IPv4 Settings** tab
6. Method: **Manual**
7. Click **Add** and enter:
   ```
   Address: 10.0.1.20
   Netmask: 255.255.255.0
   Gateway: 10.0.1.1
   ```
8. DNS servers: `10.0.0.53,8.8.8.8`
9. Search domains: `example.com`
10. Click **Save**
11. Toggle switch to **ON** to enable interface
12. Click **Done**

##### Installation Destination

**Option A: Automatic (Simple)**

1. Click **Installation Destination**
2. Select disk
3. Storage Configuration: **Automatic**
4. Click **Done**

**Option B: Custom (Recommended for Production)**

1. Click **Installation Destination**
2. Select disk(s)
3. Storage Configuration: **Custom**
4. Click **Done**
5. Click **+** to add mount points:

```
/boot       1 GiB     Standard Partition  ext4
/           20 GiB    Standard Partition  ext4
/tmp        5 GiB     Standard Partition  ext4
/var        20 GiB    Standard Partition  ext4
/var/log    10 GiB    Standard Partition  ext4
/home       10 GiB    Standard Partition  ext4
swap        4 GiB     Standard Partition  swap
```

6. Click **Done** → **Accept Changes**

##### Software Selection

1. Click **Software Selection**
2. Base Environment: **Minimal Install**
3. Add-ons: **Deselect all**
4. Click **Done**

##### Root Password

1. Click **Root Password**
2. Enter strong password
3. **Important:** Check **Lock root account** (recommended)
   - If unchecked, playbooks will lock it later
4. Click **Done**

##### User Creation

1. Click **User Creation**
2. Full name: `System Administrator`
3. User name: `sysadmin`
4. Check **Make this user administrator**
5. Set password
6. Click **Done**

#### Step 4: Begin Installation

1. Click **Begin Installation**
2. Wait for installation (5-10 minutes)
3. Click **Reboot System** when complete
4. Remove installation media

#### Step 5: First Login (AlmaLinux)

```bash
# Login with created user
login: sysadmin
password: [your password]

# Become root (if needed)
sudo -i

# Update system
dnf update -y

# Set timezone
timedatectl set-timezone America/New_York  # Adjust as needed

# Verify network
ip addr show
ping -c 3 8.8.8.8

# Check hostname
hostnamectl

# If hostname incorrect:
hostnamectl set-hostname app02.example.com

# Exit root
exit
```

## Post-Installation Configuration

Perform these steps on each newly installed server **before** running Ansible playbooks.

### 1. Copy SSH Public Key

From your **Ansible control node**:

```bash
# Copy SSH key to server (replace with your details)
ssh-copy-id -i ~/.ssh/ansible_ed25519.pub sysadmin@10.0.1.10

# Test SSH connection
ssh -i ~/.ssh/ansible_ed25519 sysadmin@10.0.1.10

# Test sudo access
ssh -i ~/.ssh/ansible_ed25519 sysadmin@10.0.1.10 'sudo whoami'
# Should return: root
```

If `ssh-copy-id` is not available:

```bash
# Manual method
cat ~/.ssh/ansible_ed25519.pub | ssh sysadmin@10.0.1.10 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys'
```

### 2. Configure Passwordless Sudo (Optional)

If you want passwordless sudo for Ansible (can be more secure than storing password):

On the **target server**:

```bash
sudo visudo -f /etc/sudoers.d/sysadmin
```

Add:
```
sysadmin ALL=(ALL) NOPASSWD: ALL
```

Save and exit. Test:

```bash
sudo whoami  # Should not prompt for password
```

**Note:** Playbooks will configure more restrictive sudo later.

### 3. Verify System Requirements

On **each server**:

```bash
# Check OS version
cat /etc/os-release

# Check disk space
df -h

# Check memory
free -h

# Check CPU
lscpu

# Check network connectivity
ping -c 3 google.com

# Check DNS resolution
nslookup example.com
```

### 4. Static IP Verification

Ensure IP addresses survive reboot:

```bash
# Reboot server
sudo reboot

# After reboot, verify IP
ip addr show
```

### 5. Update /etc/hosts (Optional)

On **each server**, add other servers for name resolution:

```bash
sudo tee -a /etc/hosts << EOF
10.0.1.10   app01.example.com   app01
10.0.1.20   app02.example.com   app02
10.0.2.10   db01.example.com    db01
10.0.3.10   build01.example.com build01
EOF
```

## Ansible Control Node Setup

These steps are performed on your **workstation/control node**.

### 1. Install Ansible

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install -y ansible
```

**macOS:**
```bash
brew install ansible
```

**RHEL/AlmaLinux:**
```bash
sudo dnf install -y epel-release
sudo dnf install -y ansible
```

**Using pip:**
```bash
pip3 install ansible
```

Verify installation:
```bash
ansible --version
```

### 2. Install Ansible Collections

```bash
ansible-galaxy collection install community.general
ansible-galaxy collection install ansible.posix
ansible-galaxy collection install community.postgresql
ansible-galaxy collection install community.docker
```

### 3. Install Additional Tools

```bash
# For generating password hashes
pip3 install passlib

# For vault encryption (optional)
pip3 install ansible-vault
```

### 4. Configure Ansible (Optional)

Create `~/.ansible.cfg`:

```ini
[defaults]
inventory = ./inventory/hosts.yml
host_key_checking = False
retry_files_enabled = False
timeout = 30
forks = 10
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 86400

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s
pipelining = True
```

### 5. Clone/Navigate to Playbook Directory

```bash
cd /path/to/repo/ansible/playbooks/hardened-linux
```

### 6. Configure Inventory

Edit `inventory/hosts.yml` (see next section).

### 7. Test Connectivity

```bash
# Ping all servers
ansible all -i inventory/hosts.yml -m ping

# Check sudo access
ansible all -i inventory/hosts.yml -m shell -a "whoami" -b

# Gather facts
ansible all -i inventory/hosts.yml -m setup
```

## Pre-Flight Checklist

Before running hardening playbooks, verify:

### Server Checklist

- [ ] OS installed (Ubuntu 24.04 or AlmaLinux 10.x)
- [ ] Static IP configured and tested
- [ ] Hostname set correctly
- [ ] DNS resolution working
- [ ] System updated (`apt upgrade` / `dnf update`)
- [ ] Admin user created with sudo access
- [ ] SSH service running
- [ ] SSH public key copied to server
- [ ] Passwordless SSH login working
- [ ] Sudo access working (with or without password)
- [ ] Network connectivity confirmed
- [ ] Disk partitioning appropriate for use case
- [ ] Timezone set correctly
- [ ] Server documented in inventory

### Control Node Checklist

- [ ] Ansible installed (version 2.12+)
- [ ] Required collections installed
- [ ] SSH key pair generated
- [ ] Private key permissions set (600)
- [ ] Inventory file configured
- [ ] Group variables configured
- [ ] Connectivity to all servers tested
- [ ] Playbooks downloaded/cloned
- [ ] Template files present

### Network Checklist

- [ ] Firewall rules allow initial SSH (port 22)
- [ ] Network allows control node → servers
- [ ] DNS configured (forward and reverse if needed)
- [ ] NTP/time servers accessible
- [ ] Package repositories accessible
- [ ] Internet access for package downloads

### Documentation Checklist

- [ ] Server inventory documented
- [ ] Network topology documented
- [ ] IP addressing scheme documented
- [ ] Credentials securely stored
- [ ] Backup/recovery plan in place
- [ ] Rollback plan prepared

## Next Steps

Once all checklist items are complete:

1. **Review variables** in `inventory/group_vars/*.yml`
2. **Run playbooks in check mode** first:
   ```bash
   ansible-playbook -i inventory/hosts.yml ubuntu/01-basic-setup.yml --check
   ```
3. **Review check mode output**
4. **Run actual playbook**:
   ```bash
   ansible-playbook -i inventory/hosts.yml ubuntu/01-basic-setup.yml
   ```
5. **Verify hardening** using verification steps in README.md
6. **Document any changes** or issues encountered

## Common Issues and Solutions

### Issue: SSH Connection Refused

**Cause:** SSH service not running or firewall blocking

**Solution:**
```bash
# On target server
sudo systemctl status sshd
sudo systemctl start sshd
sudo systemctl enable sshd

# Check firewall (Ubuntu)
sudo ufw status
sudo ufw allow 22/tcp

# Check firewall (AlmaLinux)
sudo firewall-cmd --list-all
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --reload
```

### Issue: Permission Denied (publickey)

**Cause:** SSH key not properly copied

**Solution:**
```bash
# Re-copy SSH key
ssh-copy-id -i ~/.ssh/ansible_ed25519.pub sysadmin@server_ip

# Verify permissions on server
ssh sysadmin@server_ip
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

### Issue: Sudo Requires Password

**Cause:** Ansible expects passwordless sudo

**Solution Option 1:** Configure passwordless sudo (see above)

**Solution Option 2:** Use `--ask-become-pass`:
```bash
ansible-playbook -i inventory/hosts.yml playbook.yml --ask-become-pass
```

### Issue: Unable to Resolve Hostname

**Cause:** DNS not configured or /etc/hosts missing entry

**Solution:**
```bash
# Add to inventory with ansible_host
hosts:
  app01:
    ansible_host: 10.0.1.10  # Use IP instead of hostname
```

### Issue: Package Repository Unreachable

**Cause:** Network connectivity or proxy issues

**Solution:**
```bash
# Test connectivity
ping archive.ubuntu.com  # Ubuntu
ping repo.almalinux.org  # AlmaLinux

# If behind proxy, configure:
export http_proxy=http://proxy:3128
export https_proxy=http://proxy:3128
```

## Security Notes

1. **SSH Keys:** Keep private keys secure, never commit to version control
2. **Passwords:** Use strong passwords, store in password manager
3. **Sudo Access:** Configure minimum required privileges
4. **Network:** Ensure control node → server traffic is on trusted network
5. **Logging:** Keep logs of all installation and configuration steps
6. **Backups:** Take snapshot/backup before running hardening playbooks
7. **Testing:** Test playbooks in development environment first

## Timeline Estimate

| Task | Time Estimate |
|------|---------------|
| Planning | 2-4 hours |
| OS Installation (per server) | 30-60 minutes |
| Post-installation config (per server) | 15-30 minutes |
| Ansible control node setup | 30-60 minutes |
| Inventory configuration | 30-60 minutes |
| Testing and verification | 1-2 hours |
| **Total (3 servers)** | **6-10 hours** |

## Conclusion

Following this guide ensures servers are properly prepared for Ansible hardening playbooks. Take time to verify each step before proceeding to playbook execution.

**Remember:** Security is a journey, not a destination. Regular updates, monitoring, and review are essential.
