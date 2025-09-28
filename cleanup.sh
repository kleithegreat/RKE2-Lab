#!/bin/bash
set -e

# The prefix used for all resources.
PREFIX="rke2-lab"
# The libvirt storage pool name.
POOL="default"

echo "--- Destroying and Undefining all VMs starting with '${PREFIX}' ---"
# Loop through all VMs (running and stopped) that match the prefix
for vm in $(virsh list --all --name | grep "^${PREFIX}" || true); do
    echo "Removing VM: ${vm}"
    # Destroy the VM if it's running. Ignore errors if it's not.
    virsh destroy "${vm}" &>/dev/null || echo "${vm} was not running."
    # Undefine the VM to remove its configuration.
    virsh undefine "${vm}" --nvram &>/dev/null || echo "${vm} was already undefined."
done

echo "--- Deleting all storage volumes in pool '${POOL}' starting with '${PREFIX}' ---"
# Get volume names using a compatible command, skipping the header lines with awk
# and then filter by our project prefix.
for vol in $(virsh vol-list "${POOL}" | awk 'NR>2 {print $1}' | grep "^${PREFIX}" || true); do
    if [ -n "$vol" ]; then
        echo "Deleting volume: ${vol} from pool ${POOL}"
        virsh vol-delete --pool "${POOL}" "${vol}"
    fi
done

echo "--- Destroying and Undefining network '${PREFIX}-net' ---"
virsh net-destroy "${PREFIX}-net" &>/dev/null || echo "Network '${PREFIX}-net' was not active."
virsh net-undefine "${PREFIX}-net" &>/dev/null || echo "Network '${PREFIX}-net' was not defined."

# echo "--- Destroying and Undefining the '${POOL}' pool ---"
# virsh pool-destroy "${POOL}" &>/dev/null || echo "Pool '${POOL}' was not active."
# virsh pool-undefine "${POOL}" &>/dev/null || echo "Pool '${POOL}' was not defined."

echo "--- Deleting local Terraform and Ansible files ---"
rm -f terraform.tfstate* inventory.ini

echo "--- Restarting libvirt service to clear any in-memory state ---"
sudo systemctl restart libvirtd.service

echo "✅ Cleanup complete."