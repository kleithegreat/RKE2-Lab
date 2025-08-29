output "server_ips" {
  value = {
    for k, v in libvirt_domain.server : v.name => v.network_interface[0].addresses
  }
  description = "IP addresses of the server nodes."
}

output "agent_ips" {
  value = {
    for k, v in libvirt_domain.agent : v.name => v.network_interface[0].addresses
  }
  description = "IP addresses of the agent nodes."
}