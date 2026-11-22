# https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource
resource "null_resource" "ssh" {
  for_each = {
    for key, container in var.proxmox_linux_containers :
    key => container
    if container.ssh.enabled
  }

  provisioner "local-exec" {
    environment = {
      SSHPASS = var.proxmox_connection.password
    }

    command = <<-EOT
      sshpass -e ssh -o StrictHostKeyChecking=no root@${var.proxmox_connection.host} "pct exec ${proxmox_virtual_environment_container.this[each.key].vm_id} -- sh -s" <<'REMOTE_SCRIPT'
      set -eu

      ID=unmanaged
      . /etc/os-release 2>/dev/null || true
      if [ -z "$ID" ]; then
        ID=unmanaged
      fi

      ssh_service=
      ssh_active=0
      if command -v systemctl >/dev/null 2>&1; then
        for candidate in sshd ssh; do
          if systemctl is-active --quiet "$candidate"; then
            ssh_service=$candidate
            ssh_active=1
            break
          fi
        done
      elif command -v rc-service >/dev/null 2>&1; then
        for candidate in sshd ssh; do
          if rc-service "$candidate" status >/dev/null 2>&1; then
            ssh_service=$candidate
            ssh_active=1
            break
          fi
        done
      elif command -v service >/dev/null 2>&1; then
        for candidate in sshd ssh; do
          if service "$candidate" status >/dev/null 2>&1; then
            ssh_service=$candidate
            ssh_active=1
            break
          fi
        done
      fi

      if [ "$ssh_active" -eq 0 ] && command -v pgrep >/dev/null 2>&1 && pgrep -x sshd >/dev/null 2>&1; then
        ssh_active=1
      fi

      case "$ID" in
        debian|devuan|ubuntu)
          package_manager=apt
          ssh_service=ssh
          sudo_group=sudo
          ;;
        alpine)
          package_manager=apk
          ssh_service=sshd
          sudo_group=wheel
          ;;
        arch)
          package_manager=pacman
          ssh_service=sshd
          sudo_group=wheel
          ;;
        centos|fedora|rhel|rocky|almalinux)
          if command -v dnf >/dev/null 2>&1; then
            package_manager=dnf
          else
            package_manager=yum
          fi
          ssh_service=sshd
          sudo_group=wheel
          ;;
        gentoo)
          package_manager=emerge
          ssh_service=sshd
          sudo_group=wheel
          ;;
        nixos)
          package_manager=nix
          ssh_service=sshd
          sudo_group=wheel
          ;;
        opensuse*)
          package_manager=zypper
          ssh_service=sshd
          sudo_group=wheel
          ;;
        *)
          package_manager=auto
          sudo_group=wheel
          if getent group sudo >/dev/null 2>&1; then
            sudo_group=sudo
          fi
          if [ -z "$ssh_service" ]; then
            if command -v systemctl >/dev/null 2>&1 || command -v rc-service >/dev/null 2>&1; then
              ssh_service=sshd
            else
              ssh_service=ssh
            fi
          fi
          ;;
      esac

      if [ "$ssh_active" -eq 0 ]; then
        case "$package_manager" in
          apt)
            apt-get update
            apt-get install -y openssh-server sudo
            ;;
          apk)
            apk update
            apk add bash openssh sudo shadow
            ;;
          pacman)
            pacman -Syu --noconfirm openssh sudo
            ;;
          dnf)
            dnf install -y openssh-server sudo
            ;;
          yum)
            yum install -y openssh-server sudo
            ;;
          zypper)
            zypper --non-interactive refresh
            zypper --non-interactive install openssh sudo
            ;;
          emerge)
            emerge --ask=n net-misc/openssh app-admin/sudo
            ;;
          nix)
            nix-env -iA nixpkgs.openssh nixpkgs.sudo
            ;;
          auto)
            if command -v apk >/dev/null 2>&1; then
              apk update
              apk add bash openssh sudo shadow
            elif command -v apt-get >/dev/null 2>&1; then
              apt-get update
              apt-get install -y openssh-server sudo
            elif command -v dnf >/dev/null 2>&1; then
              dnf install -y openssh-server sudo
            elif command -v yum >/dev/null 2>&1; then
              yum install -y openssh-server sudo
            elif command -v pacman >/dev/null 2>&1; then
              pacman -Syu --noconfirm openssh sudo
            elif command -v zypper >/dev/null 2>&1; then
              zypper --non-interactive refresh
              zypper --non-interactive install openssh sudo
            elif command -v emerge >/dev/null 2>&1; then
              emerge --ask=n net-misc/openssh app-admin/sudo
            else
              echo "No supported package manager found for $ID" >&2
              exit 1
            fi
            ;;
        esac

        if command -v systemctl >/dev/null 2>&1; then
          if systemctl list-unit-files "$ssh_service.service" --no-legend | grep -q "$ssh_service.service"; then
            systemctl enable "$ssh_service"
            systemctl restart "$ssh_service"
          elif command -v service >/dev/null 2>&1; then
            service "$ssh_service" restart
          else
            echo "No service unit found for $ssh_service on $ID" >&2
            exit 1
          fi
        elif command -v rc-service >/dev/null 2>&1; then
          rc-update add "$ssh_service" default
          rc-service "$ssh_service" restart
        elif command -v update-rc.d >/dev/null 2>&1 && command -v service >/dev/null 2>&1; then
          update-rc.d "$ssh_service" defaults
          service "$ssh_service" restart
        elif command -v service >/dev/null 2>&1; then
          service "$ssh_service" restart
        else
          echo "No supported service manager found for $ID" >&2
          exit 1
        fi
      fi

      username=$(printf '%s' '${base64encode(each.value.ssh.username)}' | base64 -d)
      password=$(printf '%s' '${base64encode(each.value.ssh.password)}' | base64 -d)
      id -u "$username" >/dev/null 2>&1 || useradd -m -s /bin/bash "$username"
      printf '%s:%s\n' "$username" "$password" | chpasswd
      usermod -aG "$sudo_group" "$username"
      mkdir -p "/home/$username/.ssh"
      chown -R "$username:$username" "/home/$username/.ssh"
      REMOTE_SCRIPT
    EOT
  }

  triggers = {
    vm_id = proxmox_virtual_environment_container.this[each.key].vm_id
  }
}
# https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/download_file
resource "proxmox_download_file" "this" {
  for_each = var.proxmox_download_files

  checksum                = each.value.checksum
  checksum_algorithm      = each.value.checksum_algorithm
  content_type            = each.value.content_type
  datastore_id            = each.value.datastore_id
  decompression_algorithm = each.value.decompression_algorithm
  file_name               = each.value.file_name
  node_name               = each.value.node_name
  overwrite               = each.value.overwrite
  overwrite_unmanaged     = each.value.overwrite_unmanaged
  upload_timeout          = each.value.upload_timeout
  url                     = each.value.url
}

# https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_container
resource "proxmox_virtual_environment_container" "this" {
  for_each = var.proxmox_linux_containers

  delete_unreferenced_disks_on_destroy = each.value.delete_unreferenced_disks_on_destroy
  description                          = each.value.description
  environment_variables                = each.value.environment_variables
  hook_script_file_id                  = each.value.hook_script_file_id
  migrate                              = each.value.migrate
  node_name                            = each.value.node_name
  pool_id                              = each.value.pool_id
  protection                           = each.value.protection
  purge_on_destroy                     = each.value.purge_on_destroy
  start_on_boot                        = each.value.start_on_boot
  started                              = each.value.started
  tags                                 = each.value.tags
  template                             = each.value.template
  timeout_clone                        = each.value.timeout_clone
  timeout_create                       = each.value.timeout_create
  timeout_delete                       = each.value.timeout_delete
  timeout_migrate                      = each.value.timeout_migrate
  timeout_start                        = each.value.timeout_start
  timeout_update                       = each.value.timeout_update
  unprivileged                         = each.value.unprivileged
  vm_id                                = each.value.vm_id

  dynamic "clone" {
    for_each = each.value.clone[*]
    content {
      datastore_id = clone.value.datastore_id
      full         = clone.value.full
      node_name    = clone.value.node_name
      vm_id        = clone.value.vm_id
    }
  }

  dynamic "console" {
    for_each = each.value.console[*]
    content {
      enabled   = console.value.enabled
      tty_count = console.value.tty_count
      type      = console.value.type
    }
  }

  dynamic "cpu" {
    for_each = each.value.cpu[*]
    content {
      architecture = cpu.value.architecture
      cores        = cpu.value.cores
      units        = cpu.value.units
    }
  }

  dynamic "device_passthrough" {
    for_each = each.value.device_passthrough == null ? [] : each.value.device_passthrough

    content {
      deny_write = device_passthrough.value.deny_write
      gid        = device_passthrough.value.gid
      mode       = device_passthrough.value.mode
      path       = device_passthrough.value.path
      uid        = device_passthrough.value.uid
    }
  }

  dynamic "disk" {
    for_each = each.value.disk[*]
    content {
      acl           = disk.value.acl
      datastore_id  = disk.value.datastore_id
      mount_options = disk.value.mount_options
      quota         = disk.value.quota
      replicate     = disk.value.replicate
      size          = disk.value.size
    }
  }

  dynamic "features" {
    for_each = each.value.features[*]
    content {
      fuse    = features.value.fuse
      keyctl  = features.value.keyctl
      mknod   = features.value.mknod
      mount   = features.value.mount
      nesting = features.value.nesting
    }
  }

  dynamic "idmap" {
    for_each = each.value.idmap == null ? [] : each.value.idmap
    content {
      container_id = idmap.value.container_id
      host_id      = idmap.value.host_id
      size         = idmap.value.size
      type         = idmap.value.type
    }
  }

  dynamic "initialization" {
    for_each = each.value.initialization[*]
    content {
      entrypoint = initialization.value.entrypoint
      hostname   = initialization.value.hostname

      dynamic "dns" {
        for_each = initialization.value.dns[*]
        content {
          domain  = dns.value.domain
          server  = dns.value.server
          servers = dns.value.servers
        }
      }

      dynamic "ip_config" {
        for_each = initialization.value.ip_config[*]
        content {
          dynamic "ipv4" {
            for_each = ip_config.value.ipv4[*]
            content {
              address = ipv4.value.address
              gateway = ipv4.value.gateway
            }
          }
          dynamic "ipv6" {
            for_each = ip_config.value.ipv6[*]
            content {
              address = ipv6.value.address
              gateway = ipv6.value.gateway
            }
          }
        }
      }

      dynamic "user_account" {
        for_each = initialization.value.user_account[*]
        content {
          keys     = user_account.value.keys
          password = user_account.value.password
        }
      }
    }
  }

  dynamic "memory" {
    for_each = each.value.memory[*]
    content {
      dedicated = memory.value.dedicated
      swap      = memory.value.swap
    }
  }

  dynamic "mount_point" {
    for_each = concat(
      each.value.mount_point == null ? [] : [each.value.mount_point],
      each.value.mount_points == null ? [] : each.value.mount_points
    )
    content {
      acl           = mount_point.value.acl
      backup        = mount_point.value.backup
      mount_options = mount_point.value.mount_options
      path          = mount_point.value.path
      quota         = mount_point.value.quota
      read_only     = mount_point.value.read_only
      replicate     = mount_point.value.replicate
      shared        = mount_point.value.shared
      size          = mount_point.value.size
      volume        = mount_point.value.volume
    }
  }

  dynamic "network_interface" {
    for_each = concat(
      each.value.network_interface == null ? [] : [each.value.network_interface],
      each.value.network_interfaces == null ? [] : each.value.network_interfaces
    )
    content {
      bridge       = network_interface.value.bridge
      enabled      = network_interface.value.enabled
      firewall     = network_interface.value.firewall
      host_managed = network_interface.value.host_managed
      mac_address  = network_interface.value.mac_address
      mtu          = network_interface.value.mtu
      name         = network_interface.value.name
      rate_limit   = network_interface.value.rate_limit
      vlan_id      = network_interface.value.vlan_id
    }
  }

  dynamic "operating_system" {
    for_each = each.value.operating_system[*]
    content {
      template_file_id = lookup(
        local.template_file_ids,
        operating_system.value.template_file_id,
        operating_system.value.template_file_id
      )
      type = operating_system.value.type
    }
  }

  dynamic "startup" {
    for_each = each.value.startup[*]
    content {
      down_delay = startup.value.down_delay
      order      = startup.value.order
      up_delay   = startup.value.up_delay
    }
  }

  dynamic "wait_for_ip" {
    for_each = each.value.wait_for_ip[*]
    content {
      cidrs      = wait_for_ip.value.cidrs
      interfaces = wait_for_ip.value.interfaces
      ipv4       = wait_for_ip.value.ipv4
      ipv6       = wait_for_ip.value.ipv6
      timeout    = wait_for_ip.value.timeout
    }
  }
}

# https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_vm
resource "proxmox_virtual_environment_vm" "this" {
  for_each = var.proxmox_virtual_machines

  acpi                                 = each.value.acpi
  bios                                 = each.value.bios
  boot_order                           = each.value.boot_order
  delete_unreferenced_disks_on_destroy = each.value.delete_unreferenced_disks_on_destroy
  description                          = each.value.description
  hook_script_file_id                  = each.value.hook_script_file_id
  hotplug                              = each.value.hotplug
  keyboard_layout                      = each.value.keyboard_layout
  kvm_arguments                        = each.value.kvm_arguments
  machine                              = each.value.machine
  migrate                              = each.value.migrate
  name                                 = each.value.name
  network_device = concat(
    each.value.network_device == null ? [] : [each.value.network_device],
    each.value.network_devices == null ? [] : each.value.network_devices
  )

  node_name           = each.value.node_name
  on_boot             = each.value.on_boot
  pool_id             = each.value.pool_id
  protection          = each.value.protection
  purge_on_destroy    = each.value.purge_on_destroy
  reboot              = each.value.reboot
  reboot_after_update = each.value.reboot_after_update
  scsi_hardware       = each.value.scsi_hardware
  started             = each.value.started
  stop_on_destroy     = each.value.stop_on_destroy
  tablet_device       = each.value.tablet_device
  tags                = each.value.tags
  template            = each.value.template
  timeout_clone       = each.value.timeout_clone
  timeout_create      = each.value.timeout_create
  timeout_migrate     = each.value.timeout_migrate
  timeout_move_disk   = each.value.timeout_move_disk
  timeout_reboot      = each.value.timeout_reboot
  timeout_shutdown_vm = each.value.timeout_shutdown_vm
  timeout_start_vm    = each.value.timeout_start_vm
  timeout_stop_vm     = each.value.timeout_stop_vm
  vm_id               = each.value.vm_id

  dynamic "agent" {
    for_each = each.value.agent[*]
    content {
      enabled = agent.value.enabled
      timeout = agent.value.timeout
      trim    = agent.value.trim
      type    = agent.value.type

      dynamic "wait_for_ip" {
        for_each = agent.value.wait_for_ip[*]
        content {
          cidrs      = wait_for_ip.value.cidrs
          disabled   = wait_for_ip.value.disabled
          interfaces = wait_for_ip.value.interfaces
          ipv4       = wait_for_ip.value.ipv4
          ipv6       = wait_for_ip.value.ipv6
        }
      }
    }
  }

  dynamic "amd_sev" {
    for_each = each.value.amd_sev[*]
    content {
      allow_smt      = amd_sev.value.allow_smt
      kernel_hashes  = amd_sev.value.kernel_hashes
      no_debug       = amd_sev.value.no_debug
      no_key_sharing = amd_sev.value.no_key_sharing
      type           = amd_sev.value.type
    }
  }

  dynamic "audio_device" {
    for_each = each.value.audio_device[*]
    content {
      device  = audio_device.value.device
      driver  = audio_device.value.driver
      enabled = audio_device.value.enabled
    }
  }

  dynamic "cdrom" {
    for_each = each.value.cdrom[*]
    content {
      enabled   = cdrom.value.enabled
      file_id   = cdrom.value.file_id
      interface = cdrom.value.interface
    }
  }

  dynamic "clone" {
    for_each = each.value.clone[*]
    content {
      datastore_id = clone.value.datastore_id
      full         = clone.value.full
      node_name    = clone.value.node_name
      retries      = clone.value.retries
      vm_id        = clone.value.vm_id
    }
  }

  dynamic "cpu" {
    for_each = each.value.cpu[*]
    content {
      affinity     = cpu.value.affinity
      architecture = cpu.value.architecture
      cores        = cpu.value.cores
      flags        = cpu.value.flags
      hotplugged   = cpu.value.hotplugged
      limit        = cpu.value.limit
      numa         = cpu.value.numa
      sockets      = cpu.value.sockets
      type         = cpu.value.type
      units        = cpu.value.units
    }
  }

  dynamic "disk" {
    for_each = concat(
      each.value.disk == null ? [] : [each.value.disk],
      each.value.disks == null ? [] : each.value.disks
    )
    content {
      aio          = disk.value.aio
      backup       = disk.value.backup
      cache        = disk.value.cache
      datastore_id = disk.value.datastore_id
      discard      = disk.value.discard
      file_format  = disk.value.file_format
      file_id      = disk.value.file_id
      import_from = try(
        proxmox_download_file.this["vm-${each.key}"].id,
        disk.value.import_from
      )
      interface         = disk.value.interface
      iothread          = disk.value.iothread
      path_in_datastore = disk.value.path_in_datastore
      queues            = disk.value.queues
      replicate         = disk.value.replicate
      serial            = disk.value.serial
      size              = disk.value.size
      ssd               = disk.value.ssd

      dynamic "speed" {
        for_each = disk.value.speed[*]
        content {
          iops_read            = speed.value.iops_read
          iops_read_burstable  = speed.value.iops_read_burstable
          iops_write           = speed.value.iops_write
          iops_write_burstable = speed.value.iops_write_burstable
          read                 = speed.value.read
          read_burstable       = speed.value.read_burstable
          write                = speed.value.write
          write_burstable      = speed.value.write_burstable
        }
      }
    }
  }

  dynamic "efi_disk" {
    for_each = each.value.efi_disk[*]
    content {
      datastore_id      = efi_disk.value.datastore_id
      file_format       = efi_disk.value.file_format
      pre_enrolled_keys = efi_disk.value.pre_enrolled_keys
      type              = efi_disk.value.type
    }
  }

  dynamic "hostpci" {
    for_each = each.value.hostpci == null ? [] : each.value.hostpci
    content {
      device   = hostpci.value.device
      id       = hostpci.value.id
      mapping  = hostpci.value.mapping
      mdev     = hostpci.value.mdev
      pcie     = hostpci.value.pcie
      rom_file = hostpci.value.rom_file
      rombar   = hostpci.value.rombar
      xvga     = hostpci.value.xvga
    }
  }

  dynamic "initialization" {
    for_each = each.value.initialization[*]
    content {
      datastore_id         = initialization.value.datastore_id
      file_format          = initialization.value.file_format
      interface            = initialization.value.interface
      meta_data_file_id    = initialization.value.meta_data_file_id
      network_data_file_id = initialization.value.network_data_file_id
      type                 = initialization.value.type
      upgrade              = initialization.value.upgrade
      user_data_file_id    = initialization.value.user_data_file_id
      vendor_data_file_id  = initialization.value.vendor_data_file_id

      dynamic "dns" {
        for_each = initialization.value.dns[*]
        content {
          domain  = dns.value.domain
          servers = dns.value.servers
        }
      }

      dynamic "ip_config" {
        for_each = initialization.value.ip_config[*]
        content {
          dynamic "ipv4" {
            for_each = ip_config.value.ipv4[*]
            content {
              address = ipv4.value.address
              gateway = ipv4.value.gateway
            }
          }
          dynamic "ipv6" {
            for_each = ip_config.value.ipv6[*]
            content {
              address = ipv6.value.address
              gateway = ipv6.value.gateway
            }
          }
        }
      }

      dynamic "user_account" {
        for_each = initialization.value.user_account[*]
        content {
          keys     = user_account.value.keys
          password = user_account.value.password
          username = user_account.value.username
        }
      }
    }
  }

  dynamic "memory" {
    for_each = each.value.memory[*]
    content {
      dedicated      = memory.value.dedicated
      floating       = memory.value.floating
      hugepages      = memory.value.hugepages
      keep_hugepages = memory.value.keep_hugepages
      shared         = memory.value.shared
    }
  }

  dynamic "numa" {
    for_each = each.value.numa == null ? [] : each.value.numa
    content {
      cpus      = numa.value.cpus
      device    = numa.value.device
      hostnodes = numa.value.hostnodes
      memory    = numa.value.memory
      policy    = numa.value.policy
    }
  }

  dynamic "operating_system" {
    for_each = each.value.operating_system[*]
    content {
      type = operating_system.value.type
    }
  }

  dynamic "rng" {
    for_each = each.value.rng[*]
    content {
      max_bytes = rng.value.max_bytes
      period    = rng.value.period
      source    = rng.value.source
    }
  }

  dynamic "serial_device" {
    for_each = each.value.serial_device[*]
    content {
      device = serial_device.value.device
    }
  }

  dynamic "smbios" {
    for_each = each.value.smbios[*]
    content {
      family       = smbios.value.family
      manufacturer = smbios.value.manufacturer
      product      = smbios.value.product
      serial       = smbios.value.serial
      sku          = smbios.value.sku
      uuid         = smbios.value.uuid
      version      = smbios.value.version
    }
  }

  dynamic "startup" {
    for_each = each.value.startup[*]
    content {
      down_delay = startup.value.down_delay
      order      = startup.value.order
      up_delay   = startup.value.up_delay
    }
  }

  dynamic "tpm_state" {
    for_each = each.value.tpm_state[*]
    content {
      datastore_id = tpm_state.value.datastore_id
      version      = tpm_state.value.version
    }
  }

  dynamic "usb" {
    for_each = each.value.usb == null ? [] : each.value.usb
    content {
      host    = usb.value.host
      mapping = usb.value.mapping
      usb3    = usb.value.usb3
    }
  }

  dynamic "vga" {
    for_each = each.value.vga[*]
    content {
      clipboard = vga.value.clipboard
      memory    = vga.value.memory
      type      = vga.value.type
    }
  }

  dynamic "virtiofs" {
    for_each = each.value.virtiofs[*]
    content {
      cache        = virtiofs.value.cache
      direct_io    = virtiofs.value.direct_io
      expose_acl   = virtiofs.value.expose_acl
      expose_xattr = virtiofs.value.expose_xattr
      mapping      = virtiofs.value.mapping
    }
  }

  dynamic "watchdog" {
    for_each = each.value.watchdog[*]
    content {
      action  = watchdog.value.action
      enabled = watchdog.value.enabled
      model   = watchdog.value.model
    }
  }
}
