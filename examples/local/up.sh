#!/usr/bin/env sh
# Starts a throwaway Debian 13 VM on 127.0.0.1:$PORT (default 2222) that
# Conn3x can configure, with a fresh SSH key and its host key in
# ./known_hosts, and the web interface forwarded to 127.0.0.1:$WEB_PORT
# (default 8006). A container won't do here: the circuit installs a kernel
# and reboots into it. Needs QEMU with KVM, and cloud-localds from
# cloud-image-utils.
set -eu
cd "$(dirname "$0")"
port=${PORT:-2222}
web_port=${WEB_PORT:-8006}
url=https://cloud.debian.org/images/cloud/trixie/latest
image=debian-13-genericcloud-amd64.qcow2
cache=${XDG_CACHE_HOME:-$HOME/.cache}/circuit-proxmox
mkdir -p "$cache"

if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
  echo "No access to /dev/kvm. Add yourself to the kvm group, or run this where KVM is available." >&2
  exit 1
fi

# The image is checked against the checksums Debian publishes beside it.
curl -fsSL -o "$cache/SHA512SUMS" "$url/SHA512SUMS"
if ! (cd "$cache" && grep " $image\$" SHA512SUMS | sha512sum -c --status - 2>/dev/null); then
  curl -fsSL -o "$cache/$image" "$url/$image"
  (cd "$cache" && grep " $image\$" SHA512SUMS | sha512sum -c --quiet -)
fi

[ -f id_ed25519 ] || ssh-keygen -q -t ed25519 -N '' -C circuit-proxmox -f id_ed25519
if [ -f vm.pid ]; then kill "$(cat vm.pid)" 2>/dev/null || true; fi
rm -f disk.qcow2 seed.img vm.pid
# A copy-on-write disk over the image, so each run starts fresh.
qemu-img create -q -f qcow2 -b "$cache/$image" -F qcow2 disk.qcow2 20G
cat > user-data <<UD
#cloud-config
hostname: pve1
disable_root: false
ssh_pwauth: false
users:
  - name: root
    ssh_authorized_keys: ["$(cat id_ed25519.pub)"]
UD
cloud-localds seed.img user-data
# Proxmox asks for at least 2 GB of memory. It was tested with 4.
qemu-system-x86_64 -enable-kvm -cpu host -m "${MEMORY:-4096}" -smp "${CPUS:-2}" \
  -drive file=disk.qcow2,if=virtio -drive file=seed.img,if=virtio,format=raw \
  -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:$port-:22,hostfwd=tcp:127.0.0.1:$web_port-:8006" \
  -display none -serial file:serial.log -daemonize -pidfile vm.pid

for _ in $(seq 1 90); do
  if ssh-keyscan -T 2 -p "$port" 127.0.0.1 > known_hosts 2>/dev/null && [ -s known_hosts ] &&
    ssh -q -o BatchMode=yes -o UserKnownHostsFile=known_hosts -i id_ed25519 -p "$port" root@127.0.0.1 'cloud-init status --wait >/dev/null 2>&1; true'; then
    echo "Ready on 127.0.0.1:$port. Now run: conn3x init && conn3x apply -var port=$port"
    exit 0
  fi
  sleep 2
done
echo "The VM started, but SSH didn't answer on 127.0.0.1:$port. Its console is in serial.log." >&2
exit 1
