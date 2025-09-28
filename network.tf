resource "libvirt_network" "cluster_network" {
  count     = var.agent_nodes > 0 ? 1 : 0
  name      = "${var.cluster_name}-net"
  mode      = "nat"
  domain    = "${var.cluster_name}.local"
  addresses = [var.cluster_cidr]
  dhcp {
    enabled = true
  }
  dns {
    enabled = true
    forwarders {
      address = "1.1.1.1"
    }
    forwarders {
      address = "8.8.8.8"
    }
  }
  autostart = true
}