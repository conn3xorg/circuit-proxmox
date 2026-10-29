# Runs after examples/single-node: Conn3x made the host a Proxmox VE node,
# and OpenTofu's Proxmox provider now puts a container on it through the
# node's API.
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.119.0"
    }
  }
}

variable "address" {
  type        = string
  description = "Address of the Proxmox VE node."
}

variable "node_name" {
  type        = string
  default     = "pve1"
  description = "The node's name, its key in the circuit's hosts."
}

variable "api_token" {
  type        = string
  sensitive   = true
  description = "API token, as root@pam!ID=SECRET."
}

provider "proxmox" {
  endpoint  = "https://${var.address}:8006/"
  api_token = var.api_token
  # A fresh node serves the web interface with a self-signed certificate.
  insecure = true
}

# The node's own local storage takes templates and ISOs but not container
# disks, so containers get a directory of their own.
resource "proxmox_storage_directory" "guests" {
  id               = "guests"
  path             = "/var/lib/guests"
  nodes            = [var.node_name]
  content          = ["rootdir", "vztmpl"]
  create_base_path = true
}

resource "proxmox_download_file" "debian" {
  content_type = "vztmpl"
  datastore_id = proxmox_storage_directory.guests.id
  node_name    = var.node_name
  url          = "http://download.proxmox.com/images/system/debian-13-standard_13.6-1_amd64.tar.zst"
}

resource "proxmox_virtual_environment_container" "hello" {
  node_name    = var.node_name
  vm_id        = 100
  unprivileged = true

  features {
    nesting = true
  }

  initialization {
    hostname = "hello"
  }

  disk {
    datastore_id = proxmox_storage_directory.guests.id
    size         = 4
  }

  operating_system {
    template_file_id = proxmox_download_file.debian.id
    type             = "debian"
  }
}
