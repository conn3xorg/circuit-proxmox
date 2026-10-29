# Facts confirm each host is Debian 13 on x86_64 before anything is
# installed, and give the address its node name resolves to.
data "conn3x_host" "facts" {
  for_each = var.hosts

  ssh {
    host             = try(each.value.address, each.value)
    host_key         = try(each.value.host_key, null)
    user             = try(each.value.user, var.ssh_user)
    port             = try(each.value.port, var.ssh_port)
    private_key_file = try(each.value.private_key_file, var.ssh_private_key_file)
    jump_hosts       = try(each.value.jump_hosts, null)
    known_hosts_file = var.ssh_known_hosts_file
  }

  lifecycle {
    postcondition {
      condition     = self.os_id == "debian" && split(".", self.os_version)[0] == "13" && self.arch == "x86_64"
      error_message = "Proxmox VE 9 installs on x86_64 Debian 13 (trixie). Host ${each.key} is ${self.os_id} ${self.os_version} on ${self.arch}."
    }
    postcondition {
      condition     = try(var.hosts[each.key].node_ip, null) != null || self.ipv4 != ""
      error_message = "Host ${each.key} has no default IPv4 route to take its node address from. Set node_ip in its host object."
    }
  }
}

locals {
  name    = { for name, h in var.hosts : name => try(h.hostname, name) }
  node_ip = { for name, h in var.hosts : name => try(h.node_ip, data.conn3x_host.facts[name].ipv4) }

  # Proxmox's cluster stack finds the node's address by resolving its name,
  # and won't take a loopback address for it.
  hosts_line = { for name, n in local.name : name => join(" ", compact([
    local.node_ip[name],
    var.domain == null ? "" : "${n}.${var.domain}",
    n,
  ])) }

  # pve-manager ships the enterprise repository in pve-enterprise.sources.
  # Writing that file first means dpkg keeps this copy, so on the
  # no-subscription repository it stays off and apt update doesn't fail
  # with 401 Unauthorized.
  enterprise_sources = <<-EOT
    # Written by Conn3x. Changes here are overwritten on the next apply.
    Types: deb
    URIs: https://enterprise.proxmox.com/debian/pve
    Suites: trixie
    Components: pve-enterprise
    Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
    ${var.repository == "pve-enterprise" ? "Enabled: yes" : "Enabled: no"}
  EOT

  no_subscription_sources = <<-EOT
    # Written by Conn3x. Changes here are overwritten on the next apply.
    Types: deb
    URIs: http://download.proxmox.com/debian/pve
    Suites: trixie
    Components: pve-no-subscription
    Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
  EOT
}

circuit "proxmox" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  # On cloud images, cloud-init would put back the 127.0.1.1 line and the
  # old name on the next boot.
  step "cloud_init" {
    command {
      command = "printf '%s\\n' '# Written by Conn3x: Proxmox VE owns the name and /etc/hosts.' 'manage_etc_hosts: false' 'preserve_hostname: true' > /etc/cloud/cloud.cfg.d/99-conn3x-proxmox.cfg"
      unless  = "! test -d /etc/cloud/cloud.cfg.d || grep -qx 'manage_etc_hosts: false' /etc/cloud/cloud.cfg.d/99-conn3x-proxmox.cfg"
    }
  }

  # The short name, as Proxmox's installer sets it. The domain goes in
  # /etc/hosts, where hostname --fqdn finds it.
  step "hostname" {
    hostname {
      name = local.name[each.key]
    }
  }

  # Debian maps the name to 127.0.1.1. Proxmox's wiki says to drop that
  # line so the name has one answer.
  step "no_loopback_name" {
    line {
      path   = "/etc/hosts"
      regexp = "^127\\.0\\.1\\.1\\s"
      state  = "absent"
    }
  }

  step "hosts_entry" {
    line {
      path         = "/etc/hosts"
      regexp       = "\\s${replace(local.name[each.key], ".", "\\.")}(\\s|$)"
      line         = local.hosts_line[each.key]
      insert_after = "^127\\.0\\.0\\.1\\s"
    }
  }

  # The key is a binary keyring, so it's fetched and checked against the
  # checksum Proxmox publishes rather than written by a repository step.
  step "keyring" {
    download {
      url    = "https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg"
      sha256 = "136673be77aba35dcce385b28737689ad64fd785a797e57897589aed08db6e45"
      dest   = "/usr/share/keyrings/proxmox-archive-keyring.gpg"
    }
  }

  step "enterprise_repository" {
    file {
      path    = "/etc/apt/sources.list.d/pve-enterprise.sources"
      content = local.enterprise_sources
    }
  }

  step "no_subscription_repository" {
    for_each = var.repository == "pve-no-subscription" ? ["pve-install-repo"] : []
    file {
      path      = "/etc/apt/sources.list.d/${item.value}.sources"
      content   = local.no_subscription_sources
      on_remove = "delete"
    }
  }

  # Proxmox replaces some Debian packages with its own builds, so the
  # system is brought up to date from both before the kernel goes in.
  step "full_upgrade" {
    command {
      command  = "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade"
      triggers = sha256("${local.enterprise_sources}${var.repository}")
    }
  }

  # Proxmox's kernel pulls in grub-pc on a BIOS host. Cloud images boot
  # GRUB without that package, so its install fails until it's told which
  # disk to install to: the one holding /boot.
  step "grub_disk" {
    command {
      command = <<-EOT
        disk=$(lsblk -lnpso NAME,TYPE "$(findmnt -nvo SOURCE /boot || findmnt -nvo SOURCE /)" | awk '$2 == "disk" { print $1; exit }')
        [ -n "$disk" ] && echo "grub-pc grub-pc/install_devices multiselect $disk" | debconf-set-selections
      EOT
      unless  = "test -d /sys/firmware/efi || debconf-show grub-pc 2>/dev/null | grep -q 'install_devices: /'"
    }
  }

  # Some Proxmox packages need kernel features Debian's kernel doesn't
  # build in, so the node boots into Proxmox's kernel before they go in.
  step "kernel" {
    package {
      name = "proxmox-default-kernel"
    }
  }

  step "boot_kernel" {
    reboot {
      timeout = "15m"
    }
  }

  # "Local only" keeps postfix on loopback. apt's non-interactive default
  # would be an Internet Site listening on every address.
  step "postfix_preseed" {
    command {
      command = "echo 'postfix postfix/main_mailer_type select Local only' | debconf-set-selections"
      unless  = "dpkg -s postfix >/dev/null 2>&1 || echo get postfix/main_mailer_type | DEBIAN_FRONTEND=noninteractive debconf-communicate 2>/dev/null | grep -qx '0 Local only'"
    }
  }

  step "packages" {
    for_each = ["proxmox-ve", "postfix", "open-iscsi", "chrony"]
    package {
      name = item.value
    }
  }

  # Debian's kernel can come back as the default after a Debian point
  # release, so Proxmox says to remove it. The check refuses when the host
  # isn't running a Proxmox kernel, so it never removes the running one.
  step "remove_debian_kernel" {
    command {
      command = <<-EOT
        uname -r | grep -q -- '-pve$' || { echo "Running $(uname -r), not a Proxmox kernel. Not removing Debian's kernel." >&2; exit 1; }
        DEBIAN_FRONTEND=noninteractive apt-get -y remove $(dpkg-query -W -f '$${db:Status-Abbrev} $${Package}\n' 'linux-image-*' | awk '$1 == "ii" { print $2 }')
        update-grub
      EOT
      unless  = "! dpkg-query -W -f '$${db:Status-Abbrev}\\n' 'linux-image-*' 2>/dev/null | grep -q '^ii'"
    }
  }

  # os-prober would add the guests' disks to GRUB's boot menu.
  step "no_os_prober" {
    package {
      name  = "os-prober"
      state = "absent"
    }
  }

  step "pveproxy" {
    service {
      name    = "pveproxy"
      state   = "started"
      enabled = true
    }
  }

  step "web_ui" {
    wait_for {
      port = 8006
    }
  }
}
