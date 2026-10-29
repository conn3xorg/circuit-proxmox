variable "hosts" {
  type        = any
  description = "Hosts to turn into Proxmox VE nodes: a map of node names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file, jump_hosts, hostname or node_ip."

  validation {
    condition     = alltrue([for name, h in var.hosts : can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", try(h.hostname, name)))])
    error_message = "Each node name, the map key or a host object's hostname, must be a single DNS label of lowercase letters, digits and inner hyphens, such as \"pve1\"."
  }

  validation {
    condition     = alltrue([for h in var.hosts : try(h.node_ip, null) == null || can(regex("^(\\d{1,3}\\.){3}\\d{1,3}$", try(h.node_ip, ""))) && !startswith(try(h.node_ip, ""), "127.")])
    error_message = "A host object's node_ip must be an IPv4 address the node is reached on, not a loopback address."
  }
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}

variable "domain" {
  type        = string
  default     = null
  description = "DNS domain for the nodes, such as \"lab.example.com\". When set, each node's hostname is its name under this domain, and /etc/hosts lists both."

  validation {
    condition     = var.domain == null || can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", coalesce(var.domain, "-")))
    error_message = "domain must be a DNS domain of lowercase labels, such as \"lab.example.com\"."
  }
}

variable "repository" {
  type        = string
  default     = "pve-no-subscription"
  description = "Proxmox VE package repository: \"pve-no-subscription\", or \"pve-enterprise\", which needs a subscription key on each node."

  validation {
    condition     = contains(["pve-no-subscription", "pve-enterprise"], var.repository)
    error_message = "repository must be \"pve-no-subscription\" or \"pve-enterprise\"."
  }
}
