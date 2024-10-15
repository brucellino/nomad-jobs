terraform {
  required_version = ">=1.2.0"
  backend "consul" {
    path = "nomad/loki"
  }
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "4.4.0"
    }
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.42.0"
    }
    nomad = {
      source  = "hashicorp/nomad"
      version = "2.4.0"
    }
    consul = {
      source  = "hashicorp/consul"
      version = "2.21.0"
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

provider "nomad" {}

provider "consul" {}

resource "digitalocean_spaces_bucket" "logs" {
  region = var.doregion
  name   = "hah-logs"
  acl    = "private"
  versioning {
    enabled = true
  }
  lifecycle_rule {
    # id      = "monthly"
    enabled = true
    prefix  = "fake_"
    expiration {
      days = 14
    }
  }
  #tfsec:ignore:digitalocean-spaces-disable-force-destroy
  force_destroy = true
}

resource "consul_keys" "bucket" {
  datacenter = "dc1"

  key {
    path  = "jobs/loki/logs_bucket"
    value = digitalocean_spaces_bucket.logs.name
  }
}

resource "consul_keys" "endpoint" {
  datacenter = "dc1"

  key {
    path  = "jobs/loki/s3_endpoint"
    value = "${digitalocean_spaces_bucket.logs.region}.digitaloceanspaces.com"
  }
}

resource "nomad_job" "loki" {
  jobspec    = file("${path.module}/loki.nomad")
  depends_on = [digitalocean_spaces_bucket.logs]
  hcl2 {
    enabled  = true
    allow_fs = true
    vars = {
      "access_key" = jsondecode(data.vault_kv_secret_v2.digitalocean.data_json)["loki_spaces_key"]
      "secret_key" = jsondecode(data.vault_kv_secret_v2.digitalocean.data_json)["loki_spaces_secret"]
    }
  }
  purge_on_destroy      = false
  detach                = true
  deregister_on_destroy = false
}
