terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.6"
    }
  }
}

# Configure the libvirt provider
provider "libvirt" {
  uri = "qemu:///system"
}

# Use a local file for the SSH key
data "local_file" "ssh_public_key" {
  filename = abspath(var.ssh_public_key)
}

# Create a cloud-init disk for node configuration
resource "libvirt_cloudinit_disk" "common" {
  name      = "${var.cluster_name}-common.iso"
  pool      = libvirt_pool.default.name
  user_data = templatefile("${path.module}/cloud-init.yaml", {
    ssh_key = data.local_file.ssh_public_key.content
  })
}

# Upload the base Rocky Linux image to the libvirt storage pool
resource "libvirt_volume" "base_image" {
  name   = "${var.cluster_name}-base.qcow2"
  pool   = libvirt_pool.default.name
  source = "${path.module}/images/rocky-9-cloud.qcow2"
  format = "qcow2"
}

# --- Server Nodes ---
resource "libvirt_volume" "server_disk" {
  count          = var.server_nodes
  name           = "${var.cluster_name}-server-${count.index}.qcow2"
  base_volume_id = libvirt_volume.base_image.id
  size           = 20 * 1024 * 1024 * 1024 # 20GB
}

resource "libvirt_domain" "server" {
  count      = var.server_nodes
  name       = "${var.cluster_name}-server-${count.index}"
  memory     = var.server_memory
  vcpu       = var.server_vcpu
  cpu {
    mode = "host-passthrough"
  }
  cloudinit  = libvirt_cloudinit_disk.common.id
  autostart  = true

  network_interface {
    network_id     = libvirt_network.cluster_network.id
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.server_disk[count.index].id
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

# --- Agent Nodes ---
resource "libvirt_volume" "agent_disk" {
  count          = var.agent_nodes
  name           = "${var.cluster_name}-agent-${count.index}.qcow2"
  base_volume_id = libvirt_volume.base_image.id
  size           = 20 * 1024 * 1024 * 1024 # 20GB
}

resource "libvirt_domain" "agent" {
  count      = var.agent_nodes
  name       = "${var.cluster_name}-agent-${count.index}"
  memory     = var.agent_memory
  vcpu       = var.agent_vcpu
  cpu {
    mode = "host-passthrough"
  }
  cloudinit  = libvirt_cloudinit_disk.common.id
  autostart  = true

  network_interface {
    network_id     = libvirt_network.cluster_network.id
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.agent_disk[count.index].id
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}