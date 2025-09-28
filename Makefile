SHELL := /bin/bash

.PHONY: all create apply playbook destroy clean setup-pool ssh refresh-known-hosts \
        cluster-init testvm-init testvm-up testvm-destroy

all: create

# --- Force the default workspace for CLUSTER actions --------------------------
cluster-init:
	@terraform workspace select default >/dev/null 2>&1 || terraform workspace new default
	@echo "✅ Using Terraform workspace: default"

# Creates the full cluster: provisions VMs and then configures them with Ansible.
create: cluster-init apply playbook
	@echo "✅ Cluster creation and configuration complete."

# Provisions VMs and network infrastructure using Terraform.
apply: cluster-init
	@echo ">>> Provisioning infrastructure with Terraform..."
	terraform apply -auto-approve

# Configures the running VMs with the Ansible playbook.
# Best run after 'make apply' or as part of 'make create'.
playbook: cluster-init
	@echo ">>> Configuring nodes with Ansible..."
	ansible-playbook playbook.yml

# Destroys the infrastructure gracefully using Terraform.
destroy: cluster-init
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

refresh-known-hosts:
	@for ip in $$(awk -F= '/ansible_host/ {print $$2}' inventory.ini); do \
	  ssh-keygen -R $$ip >/dev/null 2>&1 || true; \
	  ssh-keyscan -H $$ip >> $$HOME/.ssh/known_hosts; \
	done; \
	echo "✅ known_hosts refreshed for all cluster nodes."

# --- Single, isolated TEST VM (separate Terraform workspace) ------------------

# Create/select the 'testvm' workspace so this never touches your main cluster
testvm-init:
	@terraform workspace select testvm >/dev/null 2>&1 || terraform workspace new testvm
	@echo "✅ Using Terraform workspace: testvm"

# Bring up one standalone VM with bigger RAM/CPU/disk under its own network/prefix
# Nothing else (no Ansible). Safe to run alongside your main cluster.
testvm-up: testvm-init
	@echo ">>> Provisioning isolated test VM..."
	terraform apply -auto-approve \
	  -var 'cluster_name=rke2-testvm' \
	  -var 'server_nodes=1' -var 'agent_nodes=0' \
	  -var 'server_vcpu=4' -var 'server_memory=8192' \
	  -var 'server_disk_size_gb=40' \
	  -var 'cluster_cidr=10.77.7.0/24' \
	  -target=libvirt_network.cluster_network \
	  -target=libvirt_volume.base_image \
	  -target=libvirt_cloudinit_disk.server[0] \
	  -target=libvirt_volume.server_disk[0] \
	  -target=libvirt_domain.server[0]
	@echo "✅ Test VM up (workspace: testvm, name prefix: rke2-testvm)"

# Tear down only the test VM stack in the 'testvm' workspace.
testvm-destroy: testvm-init
	@echo ">>> Destroying isolated test VM..."
	terraform destroy -auto-approve \
	  -var 'cluster_name=rke2-testvm' \
	  -var 'server_nodes=1' -var 'agent_nodes=0' \
	  -var 'server_vcpu=4' -var 'server_memory=8192' \
	  -var 'server_disk_size_gb=40' \
	  -var 'cluster_cidr=10.77.7.0/24'
	@echo "🗑️  Test VM destroyed (workspace: testvm)"
