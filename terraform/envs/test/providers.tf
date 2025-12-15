terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "= 3.0.2-rc06"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.0"
    }
  }
}

data "sops_file" "proxmox" {
  source_file = "${path.module}/../../../secrets/proxmox.enc.yaml"
}

provider "proxmox" {
  alias               = "main"
  pm_api_url          = data.sops_file.proxmox.data["pm_api_url"]
  pm_api_token_id     = data.sops_file.proxmox.data["pm_api_token_id"]
  pm_api_token_secret = data.sops_file.proxmox.data["pm_api_token_secret"]
  pm_tls_insecure     = true
}
