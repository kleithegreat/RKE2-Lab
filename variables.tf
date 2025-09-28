variable "cluster_name" {
  description = "A name for the cluster, used as a prefix for all resources."
  type        = string
  default     = "rke2-lab"
}

variable "server_nodes" {
  description = "Number of server (master) nodes to create."
  type        = number
  default     = 0
}

variable "agent_nodes" {
  description = "Number of agent (worker) nodes to create."
  type        = number
  default     = 0
}

variable "server_vcpu" {
  description = "Number of vCPUs for server nodes."
  type        = number
  default     = 2
}

variable "server_memory" {
  description = "Amount of memory in MB for server nodes."
  type        = number
  default     = 4096 # 4GB
}

variable "server_disk_size_gb" {
  description = "Disk size (GB) for server nodes."
  type        = number
  default     = 20
}

variable "agent_vcpu" {
  description = "Number of vCPUs for agent nodes."
  type        = number
  default     = 2
}

variable "agent_memory" {
  description = "Amount of memory in MB for agent nodes."
  type        = number
  default     = 2048 # 2GB
}

variable "ssh_public_key" {
  description = "Public SSH key to inject into the nodes for access."
  type        = string
  default     = "/home/child4/.ssh/id_ed25519.pub"
}

variable "cluster_cidr" {
  description = "Cluster network in CIDR notation for inter-node traffic."
  type        = string
  default     = "10.17.3.0/24"
}

variable "enable_usb_activkey" {
  type    = bool
  default = false
}
