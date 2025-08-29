resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.ini.tftpl", {
    servers = libvirt_domain.server
    agents  = libvirt_domain.agent
  })
  filename = "${path.module}/inventory.ini"
}