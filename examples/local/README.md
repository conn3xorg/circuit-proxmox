# Local example

Applies circuit-proxmox to a throwaway Debian 13 VM on your machine. The circuit installs Proxmox's kernel and reboots into it, which a container can't do, so this one is a VM. You need Conn3x, QEMU with KVM (`qemu-system-x86` and `qemu-utils` on Debian and Ubuntu), `cloud-localds` from `cloud-image-utils`, and read and write access to `/dev/kvm`, usually through the `kvm` group.

```sh
./up.sh
conn3x init
conn3x apply
conn3x plan
```

The second plan says `No changes.` The first apply reboots the VM once and takes about five minutes. To look at the result:

```sh
ssh -o UserKnownHostsFile=known_hosts -i id_ed25519 -p 2222 root@127.0.0.1 pveversion
```

It prints `pve-manager/9.x`, and the web interface answers on `https://127.0.0.1:8006`. Log in to it as root after setting a password on the VM with `passwd`.

`up.sh` downloads Debian's `genericcloud` image once, checks it against Debian's published checksums and keeps it in `~/.cache/circuit-proxmox`. Each run boots a fresh copy-on-write disk over it, with 2 CPUs and 4 GB of memory, a cloud-init seed that installs the SSH key for root, SSH on `127.0.0.1:2222` and the web interface on `127.0.0.1:8006`. Set `PORT` to use another SSH port, and pass the same port to Conn3x with `-var port=PORT`. Set `WEB_PORT` to move the other, and `CPUS` and `MEMORY` (in MB) to size the VM. The VM's console goes to `serial.log`.

`./down.sh` stops the VM and removes its disk, the key and the state. The cached image stays for the next run.
