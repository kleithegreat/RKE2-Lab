SHELL := /bin/bash

.PHONY: all create apply playbook destroy clean setup-pool ssh

all: create

# Creates the full cluster: provisions VMs and then configures them with Ansible.
create: apply playbook
	@echo "✅ Cluster creation and configuration complete."

# Provisions VMs and network infrastructure using Terraform.
apply:
	@echo ">>> Provisioning infrastructure with Terraform..."
	terraform apply -auto-approve

# Configures the running VMs with the Ansible playbook.
# Best run after 'make apply' or as part of 'make create'.
playbook:
	@echo ">>> Configuring nodes with Ansible..."
	ansible-playbook playbook.yml

# Destroys the infrastructure gracefully using Terraform.
destroy:
	@echo ">>> Destroying Terraform-managed infrastructure..."
	terraform destroy -auto-approve

# Forcefully cleans up all lab resources, including the default storage pool.
# This is a powerful fallback in case 'terraform destroy' fails.
clean:
	@echo ">>> Forcefully cleaning all lab resources (VMs, networks, disks)..."
	./cleanup.sh

# Sets up the default libvirt storage pool. Required if 'make clean' was run.
setup-pool:
	@echo ">>> Setting up the libvirt 'default' storage pool (requires sudo)..."
	sudo virsh pool-define-as --name default --type dir --target /var/lib/libvirt/images
	sudo virsh pool-build default
	sudo virsh pool-start default
	sudo virsh pool-autostart default
	@echo "✅ Libvirt 'default' pool created and started."

# A convenient shortcut to SSH into the main server node.
ssh:
	@echo ">>> Connecting to the rke2-lab-server-0 node..."
	@ssh rocky@$$(grep 'rke2-lab-server-0' inventory.ini | cut -d'=' -f2)