variable "proxmox_url" {
  description = "Proxmox API URL"
  type        = string
  default     = "https://65.109.98.48:8006/api2/json"
}

variable "proxmox_token_id" {
  description = "Proxmox API token ID"
  type        = string
}

variable "proxmox_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve-prod-02"
}

variable "ssh_public_key_file" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "vm_network_bridge" {
  description = "Network bridge for VMs"
  type        = string
  default     = "vnet0"
}

variable "vm_gateway" {
  description = "Default gateway for VMs"
  type        = string
  default     = "10.9.11.0"
}

variable "vm_dns_primary" {
  description = "Primary DNS server"
  type        = string
  default     = "8.8.8.8"
}

variable "vm_dns_secondary" {
  description = "Secondary DNS server"
  type        = string
  default     = "8.8.4.4"
}

variable "vm_searchdomain" {
  description = "DNS search domain"
  type        = string
  default     = "dzarsky.eu"
}
