terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.121.0"
    }
  }
  required_version = ">= 1.13"
}
