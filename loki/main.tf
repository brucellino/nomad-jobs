terraform {
  required_version = ">=1.2.0"
  backend "consul" {
    path = "nomad/loki"
  }
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "3.7.0"
    }
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.21.0"
    }
    nomad = {
      source  = "hashicorp/nomad"
      version = "1.4.17"
    }
  }
}

provider "vault" {
  # Configuration options
}

data "vault_kv_secret_v2" "digitalocean" {
  mount = "digitalocean"
  name  = "tokens"
}

provider "digitalocean" {
  token             = jsondecode(data.vault_kv_secret_v2.digitalocean.data_json)["terraform"]
  spaces_access_id  = jsondecode(data.vault_kv_secret_v2.digitalocean.data_json)["spaces_key"]
  spaces_secret_key = jsondecode(data.vault_kv_secret_v2.digitalocean.data_json)["spaces_secret"]
}

provider "nomad" {

}

resource "digitalocean_spaces_bucket" "logs" {
  region = var.doregion
  name   = "hah-logs"
  acl    = "private"
  lifecycle_rule {
    # id      = "monthly"
    enabled = true
    prefix  = "fake_"
    expiration {
      days = 14
    }
  }
}

# resource "nomad_job" "loki" {
#   jobspec    = templatefile("${path.module}/loki.nomad", {})
#   depends_on = [digitalocean_spaces_bucket.logs]
#   hcl2 {
#     enabled = true
#   }
# }
