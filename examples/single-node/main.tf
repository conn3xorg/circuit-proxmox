variable "address" {
  type        = string
  description = "Public address of an x86_64 Debian 13 host."
}

variable "ssh_private_key_file" {
  type    = string
  default = "~/.ssh/id_ed25519"
}

variable "ssh_known_hosts_file" {
  type    = string
  default = null
}

module "proxmox" {
  source = "../.."

  hosts                = { pve1 = var.address }
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
}

output "web_urls" {
  value = module.proxmox.web_urls
}
