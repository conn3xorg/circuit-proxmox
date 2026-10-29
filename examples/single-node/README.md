# Single-node example

Turns one Debian 13 host into a Proxmox VE node called `pve1`. You need Conn3x and an x86_64 Debian 13 server you can log in to as root with an SSH key, such as a cloud VM with 4 GB of memory. There's no container version of this example: the circuit installs a kernel and reboots into it, which a container can't do.

```sh
conn3x init
conn3x apply -var address=203.0.113.10
conn3x plan -var address=203.0.113.10
```

The second plan says `No changes.` The first apply reboots the host once and takes a few minutes. To look at the result:

```sh
ssh root@203.0.113.10 pveversion
```

It prints `pve-manager/9.x`, and the web interface answers on `https://203.0.113.10:8006`. Set `ssh_private_key_file` if your key isn't `~/.ssh/id_ed25519`, and `ssh_known_hosts_file` to check the host key against a file other than `~/.ssh/known_hosts`.

The web interface is open on the host's public address. Put a firewall in front of it, or delete the server when you're done.
