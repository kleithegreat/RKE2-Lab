locals {
  server_addrs = {
    for d in libvirt_domain.server :
    d.name => try(d.network_interface[0].addresses[0], "")
  }

  agent_addrs = {
    for d in libvirt_domain.agent :
    d.name => try(d.network_interface[0].addresses[0], "")
  }
}

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.ini.tftpl", {
    servers       = local.server_addrs
    agents        = local.agent_addrs
    cluster_cidr  = var.cluster_cidr
    open_nodeports = false
  })
  filename = "${path.module}/inventory.ini"
}
