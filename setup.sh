#!/usr/bin/env bash
set -euo pipefail

# ---------- Config ----------
CLOUD_IMG_URL="https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
LIBVIRT_CONN="qemu:///system"
NETWORK_NAME="${NETWORK_NAME:-default}"
LAB="RKE2-Lab"
ROOT="/var/lib/libvirt/images/${LAB}"
IMGDIR="${ROOT}/images"
BASE_IMG="${IMGDIR}/rocky9-base.qcow2"

SERVERS=( rke2-server1 )
SERVER_IPS=( 192.168.122.10 )
SERVER_MACS=( 52:54:00:00:10:01 )

WORKERS=( rke2-worker1 rke2-worker2 )
WORKER_IPS=( 192.168.122.11 192.168.122.12 )
WORKER_MACS=( 52:54:00:00:10:02 52:54:00:00:10:03 )

MEM_SERVER=4096 VCPUS_SERVER=2
MEM_WORKER=4096 VCPUS_WORKER=2

LOGIN_USER="rocky"
SSH_PUBKEY="${SSH_PUBKEY:-$HOME/.ssh/id_ed25519.pub}"
SSH_PRIVKEY="${SSH_PUBKEY%.pub}"
RKE2_CHANNEL="${RKE2_CHANNEL:-}"
REBUILD="${REBUILD:-false}"

# Wait windows (tunable)
WAIT_SSH_SECS="${WAIT_SSH_SECS:-900}"

# ---------- Helpers ----------
vsh(){ sudo virsh -c "$LIBVIRT_CONN" "$@"; }
need(){ command -v "$1" >/dev/null || { echo "Missing $1"; exit 1; }; }
vm_defined(){ vsh dominfo "$1" >/dev/null 2>&1; }
ts(){ date "+%H:%M:%S"; }

ensure_deps(){
  sudo apt-get update -y
  sudo apt-get install -y \
    qemu-system-x86 libvirt-daemon-system libvirt-clients virtinst \
    cloud-image-utils ovmf dnsmasq-base bridge-utils iptables \
    curl netcat-openbsd iputils-ping
  sudo systemctl enable --now libvirtd
  sudo install -d -m 0755 "$ROOT" "$IMGDIR"
  sudo chown libvirt-qemu:kvm "$ROOT" "$IMGDIR"
}

ensure_network(){
  echo "[$(ts)] Ensuring libvirt network: ${NETWORK_NAME}"
  if ! vsh net-list --all | grep -qw "$NETWORK_NAME"; then
    cat >/tmp/net.xml <<'EOF'
<network>
  <name>default</name>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
EOF
    vsh net-define /tmp/net.xml; rm -f /tmp/net.xml
  fi
  vsh net-autostart "$NETWORK_NAME" || true
  vsh net-start "$NETWORK_NAME" || true
  echo "[$(ts)] Network status:"; vsh net-info "$NETWORK_NAME" || true
}

ensure_reservation(){ # name mac ip (kept for completeness; not relied on)
  local name="$1" mac="$2" ip="$3"
  local cur; cur="$(vsh net-dumpxml "$NETWORK_NAME")"
  if grep -q "mac='${mac}'" <<<"$cur"; then
    grep -q "mac='${mac}'.*ip='${ip}'" <<<"$cur" || \
      vsh net-update "$NETWORK_NAME" modify ip-dhcp-host "<host mac='${mac}' name='${name}' ip='${ip}'/>" --live --config
  else
    vsh net-update "$NETWORK_NAME" add ip-dhcp-host "<host mac='${mac}' name='${name}' ip='${ip}'/>" --live --config
  fi
}

fetch_image(){
  if [[ ! -f "$BASE_IMG" ]]; then
    echo "[$(ts)] Fetching cloud image..."
    tmp="$(mktemp /tmp/rocky9.XXXXXX.qcow2)"
    curl -L --fail "$CLOUD_IMG_URL" -o "$tmp"
    sudo mv "$tmp" "$BASE_IMG"; sudo chown libvirt-qemu:kvm "$BASE_IMG"; sudo chmod 0644 "$BASE_IMG"
  fi
}

ensure_token(){
  if [[ ! -f "${ROOT}/.rke2_token" ]]; then
    sudo bash -c "umask 077; openssl rand -hex 16 > ${ROOT}/.rke2_token"
  fi
}

netcfg_static(){ # ip -> writes a NoCloud v1 network-config for eth0
  local ip="$1"
  local gw="192.168.122.1"
  cat <<EOF
version: 1
config:
  - type: physical
    name: eth0
    subnets:
      - type: static
        address: ${ip}/24
        gateway: ${gw}
        dns_nameservers:
          - ${gw}
          - 1.1.1.1
EOF
}

user_data(){ # name role server_ip token
  local name="$1" role="$2" server_ip="$3" token="$4"
  local key; key="$(cat "$SSH_PUBKEY")"
  cat <<EOF
#cloud-config
hostname: ${name}
manage_etc_hosts: true
ssh_pwauth: false
package_update: true
packages:
  - qemu-guest-agent
  - openssh-server
  - firewalld
users:
  - name: ${LOGIN_USER}
    groups: wheel,users
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ${key}
write_files:
  - path: /etc/rancher/rke2/config.yaml
    permissions: '0644'
    owner: root:root
    content: |
$(if [[ "$role" == "server" ]]; then cat <<'CFG'
      node-name: REPLACEME
      tls-san:
        - REPLACEME
      write-kubeconfig-mode: "0644"
      token: REPLACE_TOKEN
CFG
else cat <<'CFG'
      node-name: REPLACEME
      server: https://REPLACE_SERVER_IP:9345
      token: REPLACE_TOKEN
CFG
fi)
runcmd:
  - systemctl enable --now qemu-guest-agent
  - systemctl enable --now sshd || systemctl enable --now ssh
  - bash -lc 'command -v firewall-cmd && firewall-cmd --permanent --add-service=ssh && firewall-cmd --reload || true'
$(if [[ "$role" == "server" ]]; then cat <<SRV
  - bash -lc 'curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL="${RKE2_CHANNEL}" sh -'
  - systemctl enable --now rke2-server
SRV
else cat <<WRK
  - bash -lc 'curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL="${RKE2_CHANNEL}" INSTALL_RKE2_TYPE="agent" sh -'
  - systemctl enable --now rke2-agent
WRK
fi)
final_message: "Cloud-init for ${name} finished."
EOF
}

ensure_vm(){ # name role ip mac mem vcpus server_ip
  local name="$1" role="$2" ip="$3" mac="$4" mem="$5" vcpus="$6" server_ip="$7"
  local vm_dir="${ROOT}/${name}"
  local disk="${vm_dir}/${name}.qcow2"
  sudo install -d -m 0755 "$vm_dir"; sudo chown libvirt-qemu:kvm "$vm_dir"

  if [[ "$REBUILD" == "true" && $(vm_defined "$name" && echo yes || echo no) == "yes" ]]; then
    echo "[$(ts)] Rebuilding ${name}..."
    vsh domstate "$name" | grep -qi running && vsh destroy "$name" || true
    vsh undefine "$name" --nvram --snapshots-metadata || vsh undefine "$name" || true
    sudo rm -f "$disk"
  fi

  ensure_reservation "$name" "$mac" "$ip"

  if ! vm_defined "$name"; then
    [[ -f "$disk" ]] || { sudo qemu-img create -f qcow2 -F qcow2 -o backing_file="$BASE_IMG" "$disk"; sudo chown libvirt-qemu:kvm "$disk"; }

    local ud nc token udtmp
    token="$(sudo cat "${ROOT}/.rke2_token")"
    udtmp="$(mktemp)"
    user_data "$name" "$role" "$server_ip" "$token" > "$udtmp"
    # Replace placeholders for clarity/readability above
    sed -i "s/REPLACEME/${name}/g; s/REPLACE_TOKEN/${token}/g; s/REPLACE_SERVER_IP/${server_ip}/g" "$udtmp"
    ud="$udtmp"
    nc="$(mktemp)"; printf "network:\n" > "$nc"; netcfg_static "$ip" >> "$nc"

    echo "[$(ts)] Creating domain ${name}..."
    # Try UEFI (non-secure) first; if that fails, retry BIOS.
    if ! sudo virt-install --connect "$LIBVIRT_CONN" \
      --name "$name" \
      --memory "$mem" --vcpus "$vcpus" --cpu host-passthrough \
      --import \
      --disk "path=$disk,format=qcow2,bus=virtio,boot.order=1" \
      --network "network=${NETWORK_NAME},model=virtio,mac=${mac}" \
      --os-variant rocky9 \
      --graphics none \
      --rng /dev/urandom \
      --channel "unix,mode=bind,target_type=virtio,name=org.qemu.guest_agent.0" \
      --cloud-init "user-data=${ud},network-config=${nc}" \
      --boot uefi \
      --noautoconsole --autostart --check all=off >/dev/null 2>&1; then

      echo "[$(ts)] virt-install with UEFI failed; retrying without UEFI..."
      sudo virt-install --connect "$LIBVIRT_CONN" \
        --name "$name" \
        --memory "$mem" --vcpus "$vcpus" --cpu host-passthrough \
        --import \
        --disk "path=$disk,format=qcow2,bus=virtio,boot.order=1" \
        --network "network=${NETWORK_NAME},model=virtio,mac=${mac}" \
        --os-variant rocky9 \
        --graphics none \
        --rng /dev/urandom \
        --channel "unix,mode=bind,target_type=virtio,name=org.qemu.guest_agent.0" \
        --cloud-init "user-data=${ud},network-config=${nc}" \
        --noautoconsole --autostart --check all=off >/dev/null
    fi

    rm -f "$ud" "$nc"
  else
    vsh autostart "$name" || true
    vsh domstate "$name" | grep -qi running || vsh start "$name" || true
  fi

  # Show the NIC so we can see it's attached
  vsh domiflist "$name" || true
}

wait_for_ssh(){ # ip
  local ip="$1"
  ssh-keygen -R "$ip" >/dev/null 2>&1 || true
  printf "[%s] Waiting for SSH on %s " "$(ts)" "$ip" >&2
  local end=$((SECONDS + WAIT_SSH_SECS))
  while (( SECONDS < end )); do
    if ping -c1 -W1 "$ip" >/dev/null 2>&1 && nc -z -w2 "$ip" 22 2>/dev/null; then
      if ssh -i "$SSH_PRIVKEY" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=4 "${LOGIN_USER}@${ip}" true 2>/dev/null; then
        echo "✓" >&2
        return 0
      fi
    fi
    printf "." >&2
    sleep 2
  done
  echo >&2
  echo "ERROR: SSH not ready on ${ip} within ${WAIT_SSH_SECS}s" >&2
  return 1
}

test_ssh(){ # name ip
  local name="$1" ip="$2"
  echo "[$(ts)] Testing ${name} (${ip})..."
  ssh -i "$SSH_PRIVKEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${LOGIN_USER}@${ip}" \
    'echo -n "host: "; hostname; echo -n "kernel: "; uname -r;
     echo -n "sshd: "; systemctl is-active sshd || systemctl is-active ssh;
     (systemctl is-active rke2-server 2>/dev/null || echo "inactive") | sed "s/^/rke2-server: /";
     (systemctl is-active rke2-agent  2>/dev/null || echo "inactive") | sed "s/^/rke2-agent:  /"'
}

# ---------- Main ----------
for b in virsh virt-install qemu-img curl nc ping; do need "$b"; done
ensure_deps
ensure_network
fetch_image
ensure_token

echo "[$(ts)] Creating/starting VMs..."
for i in "${!SERVERS[@]}"; do
  ensure_vm "${SERVERS[$i]}" server "${SERVER_IPS[$i]}" "${SERVER_MACS[$i]}" "$MEM_SERVER" "$VCPUS_SERVER" "${SERVER_IPS[0]}"
done
for i in "${!WORKERS[@]}"; do
  ensure_vm "${WORKERS[$i]}" worker "${WORKER_IPS[$i]}" "${WORKER_MACS[$i]}" "$MEM_WORKER" "$VCPUS_WORKER" "${SERVER_IPS[0]}"
done

# Wait for SSH using the *known* static IPs (no DHCP dependency)
for ip in "${SERVER_IPS[@]}" "${WORKER_IPS[@]}"; do wait_for_ssh "$ip"; done

echo
for i in "${!SERVERS[@]}"; do test_ssh "${SERVERS[$i]}" "${SERVER_IPS[$i]}"; done
for i in "${!WORKERS[@]}"; do test_ssh "${WORKERS[$i]}" "${WORKER_IPS[$i]}"; done

echo
echo "SSH shortcuts:"
for i in "${!SERVERS[@]}"; do echo "  ssh -i ${SSH_PRIVKEY} ${LOGIN_USER}@${SERVER_IPS[$i]}   # ${SERVERS[$i]}"; done
for i in "${!WORKERS[@]}"; do echo "  ssh -i ${SSH_PRIVKEY} ${LOGIN_USER}@${WORKER_IPS[$i]}   # ${WORKERS[$i]}"; done
