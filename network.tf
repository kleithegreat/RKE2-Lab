resource "libvirt_network" "cluster_network" {
  name      = "${var.cluster_name}-net"
  mode      = "nat"
  domain    = "${var.cluster_name}.local"
  addresses = ["10.17.3.0/24"]
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