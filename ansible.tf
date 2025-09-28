resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.ini.tftpl", {
    servers = libvirt_domain.server
    agents  = libvirt_domain.agent
    cluster_cidr = var.cluster_cidr
    open_nodeports = false
  })
  filename = "${path.module}/inventory.ini"
}