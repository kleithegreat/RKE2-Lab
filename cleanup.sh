#!/bin/bash
set -e

URI="qemu:///system"
PREFIX="${1:-rke2-lab}"
POOL="default"

echo "--- Destroying and Undefining all VMs starting with '${PREFIX}' ---"
for vm in $(virsh -c "$URI" list --all --name | grep "^${PREFIX}" || true); do
  echo "Removing VM: ${vm}"
  virsh -c "$URI" destroy "$vm" &>/dev/null || echo "${vm} was not running."
  virsh -c "$URI" undefine "$vm" --nvram &>/dev/null || echo "${vm} was already undefined."
done

echo "--- Deleting all storage volumes in pool '${POOL}' starting with '${PREFIX}' ---"
for vol in $(virsh -c "$URI" vol-list "$POOL" | awk 'NR>2 {print $1}' | grep "^${PREFIX}" || true); do
  [ -n "$vol" ] && virsh -c "$URI" vol-delete --pool "$POOL" "$vol" || true
done

echo "--- Destroying and Undefining network '${PREFIX}-net' ---"
virsh -c "$URI" net-destroy  "${PREFIX}-net" &>/dev/null || echo "Network '${PREFIX}-net' was not active."
virsh -c "$URI" net-undefine "${PREFIX}-net" &>/dev/null || echo "Network '${PREFIX}-net' was not defined."

echo "--- Deleting local Terraform and Ansible files ---"
rm -rf terraform.tfstate terraform.tfstate.backup .terraform terraform.tfstate.d inventory.ini || true

echo "--- Restarting libvirt service to clear any in-memory state ---"
sudo systemctl restart libvirtd.service
echo "✅ Cleanup complete."