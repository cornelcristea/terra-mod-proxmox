# terra-mod-proxmox

This module manages Proxmox downloads, Linux containers (LXC), and virtual
machines using the `bpg/proxmox` provider. Configure the provider in the calling
Terraform or OpenTofu configuration.

## Requirements

| Name | Version |
| --- | --- |
| OpenTofu or Terraform | Compatible with the `bpg/proxmox` provider |
| `bpg/proxmox` | `0.121.0` |

## Usage

```hcl
module "proxmox" {
  source = "git::https://github.com/cornelcristea/terra-mod-proxmox.git?ref=main"

  proxmox_download_files = {
    debian = {
      content_type = "vztmpl"
      datastore_id = "local"
      node_name    = "pve"
      url          = "https://example.test/debian-template.tar.zst"
    }
  }

  proxmox_linux_containers = {
    app = {
      node_name = "pve"
      vm_id     = 101
      initialization = {
        hostname = "app"
      }
      operating_system = {
        type             = "debian"
        template_file_id = "debian"
      }
      cpu = {
        cores = 2
      }
      memory = {
        dedicated = 2048
      }
      disk = {
        datastore_id = "local-lvm"
        size         = 8
      }
      network_interface = {
        name   = "eth0"
        bridge = "vmbr0"
      }
    }
  }

  proxmox_virtual_machines = {
    api = {
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
        size         = 32
      }
      network_device = {
        bridge = "vmbr0"
        model  = "virtio"
      }
    }
  }
}
```

The map keys (`debian`, `app`, `api`) identify resources within this module.
Set the provider connection and credentials outside the module, following the
[`bpg/proxmox` provider documentation](https://registry.terraform.io/providers/bpg/proxmox/latest/docs).

## Downloads

`proxmox_download_files` manages files in Proxmox storage. Each entry requires
`datastore_id`, `node_name`, and `url`; other supported options include
`content_type`, checksums, overwrite behavior, and upload timeout.

For LXC templates, `operating_system.template_file_id` can be a key from
`proxmox_download_files`; the module resolves it to the downloaded file ID.
For VM disk imports, a download entry keyed as `vm-<vm-map-key>` is used as the
disk's `import_from` file ID. If there is no matching download entry, the
configured `disk.import_from` value is passed through.

## Linux containers

`proxmox_linux_containers` exposes the configurable arguments and blocks
supported by `bpg/proxmox`'s `proxmox_virtual_environment_container`. The
provider's top-level `template` option is exposed as `template`.
`initialization.entrypoint` and `operating_system.template_file_id` are passed
through.

The `mount_point` and `network_interface` inputs accept a single object for
compatibility. Use `mount_points` and `network_interfaces` lists to configure
multiple blocks; singular and plural forms can be combined.

## Virtual machines

`proxmox_virtual_machines` exposes the configurable arguments and blocks
supported by `bpg/proxmox`'s `proxmox_virtual_environment_vm`. The provider's
top-level `template` option is exposed as `template`.

The `disk` and `network_device` inputs accept a single object for compatibility.
Use `disks` and `network_devices` lists to configure multiple blocks; singular
and plural forms can be combined.

## SSH provisioning for containers

Set `ssh.enabled` on a container to provision SSH and configure its user. The
provisioner connects from the machine running Terraform/OpenTofu to the
Proxmox host as `root`, then runs `pct exec` on that host. The local machine
must have `sshpass` and SSH access to the Proxmox host.

Provide the Proxmox host and password with `proxmox_connection`, and set the
SSH username and password per container:

```hcl
proxmox_connection = {
  host     = "192.0.2.10"
  password = var.proxmox_root_password
}

proxmox_linux_containers = {
  app = {
    # Other container settings...
    ssh = {
      enabled  = true
      username = "appuser"
      password = var.app_ssh_password
    }
  }
}
```

Treat these credentials as secrets. SSH setup supports Alpine, Arch Linux,
CentOS, Debian, Devuan, Fedora, Gentoo, NixOS, openSUSE, and Ubuntu, with
best-effort package-manager detection for unmanaged containers. When an SSH
daemon is already active, package installation and service setup are skipped,
but the requested user and password are still configured. NixOS may require
declarative system configuration for a persistent SSH service; unmanaged
images may not be fully compatible with automatic setup.

## Inputs

| Name | Type | Description |
| --- | --- | --- |
| `proxmox_connection` | Object (sensitive) | Proxmox host and password used by SSH provisioning. Defaults to `{}`. |
| `proxmox_download_files` | Map of objects | Proxmox file downloads keyed by a local identifier. Defaults to `{}`. |
| `proxmox_linux_containers` | Map of objects | LXC configurations keyed by a local identifier. Defaults to `{}`. |
| `proxmox_virtual_machines` | Map of objects | VM configurations keyed by a local identifier. Defaults to `{}`. |

Each map value supports the corresponding options documented by the
`bpg/proxmox` resource, as typed in `variables.tf`.

## Outputs

| Name | Description |
| --- | --- |
| `proxmox_lxc_names` | LXC hostnames, or map keys when no hostname is configured. |
| `proxmox_lxc_ipv4_addresses` | Configured LXC IPv4 addresses, or map keys when none are configured. |
| `proxmox_vm_names` | VM names, or map keys when no name is configured. |
| `proxmox_vm_ipv4_addresses` | IPv4 addresses reported by the QEMU guest agent for each VM. |

## Tests

Run the module's mocked OpenTofu tests from the module directory:

```sh
./tests/test.sh
```
