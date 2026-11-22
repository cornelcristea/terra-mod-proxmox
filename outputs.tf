output "proxmox_lxc_names" {
  description = "Names of the configured LXC"
  value = {
    for key, lxc in var.proxmox_linux_containers :
    key => coalesce(try(lxc.initialization.hostname, null), key)
  }
}

output "proxmox_lxc_ipv4_addresses" {
  description = "IPv4 addresses of the configured LXC"
  value = {
    for key, lxc in var.proxmox_linux_containers :
    key => coalesce(try(lxc.initialization.ip_config.ipv4.address, null), key)
  }
}

output "proxmox_vm_names" {
  description = "Names of the configured VM"
  value = {
    for key, vm in var.proxmox_virtual_machines :
    key => coalesce(vm.name, key)
  }
}

output "proxmox_vm_ipv4_addresses" {
  description = "IPv4 addresses reported by the QEMU guest agent for each VM"
  value = {
    for key, vm in proxmox_virtual_environment_vm.this :
    key => vm.ipv4_addresses
  }
}
