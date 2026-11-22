mock_provider "proxmox" {
  mock_resource "proxmox_download_file" {
    defaults = {
      id = "local:vztmpl/template.tar.zst"
    }
  }
}

run "proxmox_download_files" {
  command = plan

  variables {
    proxmox_download_files = {
      debian = {
        content_type = "vztmpl"
        datastore_id = "local"
        node_name    = "pve"
        url          = "https://example.test/debian.tar.zst"
      }
    }
  }

  assert {
    condition     = length(proxmox_download_file.this) == 1
    error_message = "Configured download files should be planned."
  }

  assert {
    condition     = proxmox_download_file.this["debian"].url == "https://example.test/debian.tar.zst"
    error_message = "The configured download file URL should be passed through."
  }
}

run "proxmox_linux_containers" {
  command = plan

  variables {
    proxmox_linux_containers = {
      lxc01 = {
        node_name = "pve"
        vm_id     = 101
        initialization = {
          hostname = "app"
        }
        device_passthrough = [
          {
            path = "/dev/net/tun"
            mode = "0666"
          }
        ]
        ssh = {
          enabled  = true
          username = "test-user"
          password = "test-password"
        }
      }
      lxc02 = {
        node_name = "pve"
        vm_id     = 102
        initialization = {
          hostname = "database"
        }
        ssh = {
          enabled  = false
          username = "test-user"
          password = "test-password"
        }
      }
    }
  }

  assert {
    condition = output.proxmox_lxc_names == {
      lxc01 = "app"
      lxc02 = "database"
    }
    error_message = "Each configured LXC should have its hostname returned, keyed by its map key."
  }

  assert {
    condition     = output.proxmox_vm_names == {}
    error_message = "No VM names should be returned when only LXC instances are configured."
  }

  assert {
    condition     = length(proxmox_virtual_environment_container.this) == 2
    error_message = "All configured LXC instances should be planned."
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.this) == 0
    error_message = "No VM resources should be planned when only LXC instances are configured."
  }

  assert {
    condition     = toset(keys(null_resource.ssh)) == toset(["lxc01"])
    error_message = "SSH should be configured only for containers with ssh.enabled set to true."
  }

  assert {
    condition     = null_resource.ssh["lxc01"].triggers.vm_id == "101"
    error_message = "The SSH resource should target the VM ID of its matching container."
  }
}

run "proxmox_virtual_machines" {
  command = plan

  variables {
    proxmox_virtual_machines = {
      vm01 = {
        name      = "api"
        node_name = "pve"
        vm_id     = 201
        cpu = {
          cores   = 2
          sockets = 1
        }
        memory = {
          dedicated = 2048
        }
        disk = {
          datastore_id = "local-lvm"
          interface    = "scsi0"
        }
      }
      vm02 = {
        name      = "server"
        node_name = "pve"
        vm_id     = 202
        cpu = {
          cores   = 2
          sockets = 1
        }
        memory = {
          dedicated = 2048
        }
        disk = {
          datastore_id = "local-lvm"
          interface    = "scsi0"
        }
      }
    }
  }

  assert {
    condition     = output.proxmox_lxc_names == {}
    error_message = "No LXC names should be returned when only VMs are configured."
  }

  assert {
    condition = output.proxmox_vm_names == {
      vm01 = "api"
      vm02 = "server"
    }
    error_message = "Each configured VM should have its configured name or map key returned."
  }

  assert {
    condition = (
      proxmox_virtual_environment_vm.this["vm01"].vm_id == 201 &&
      proxmox_virtual_environment_vm.this["vm02"].vm_id == 202
    )
    error_message = "Each configured VM should use its configured VM ID."
  }

  assert {
    condition     = toset(keys(output.proxmox_vm_ipv4_addresses)) == toset(["vm01", "vm02"])
    error_message = "Each configured VM should have an IPv4 address output, keyed by its map key."
  }

  assert {
    condition     = length(proxmox_virtual_environment_container.this) == 0
    error_message = "No LXC resources should be planned when only VMs are configured."
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.this) == 2
    error_message = "All configured VM instances should be planned."
  }
}
