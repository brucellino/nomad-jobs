terraform {
  backend "consul" {
    scheme = "http"
    path   = "terraform/personal/github-runners"
  }
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    nomad = {
      source  = "hashicorp/nomad"
      version = "~> 2.0"
    }
  }
}

variable "org_name" {
  description = "Name of the Github organisation"
  default     = "SouthAfricaDigitalScience"
  sensitive   = false
  type        = string
}

provider "vault" {
  address = "http://sense:8200"
}

provider "nomad" {}

data "vault_kv_secret_v2" "name" {
  mount = "kv"
  name  = "github"
}

provider "github" {
  token = data.vault_kv_secret_v2.name.data.personal
}

data "github_organization" "sads" {
  name = var.org_name
}

locals {
  runners_api_url = "https://api.github.com/orgs/${var.org_name}/actions/runners"
  headers = {
    "Accept"               = "application/vnd.github+json"
    "Authorization"        = "Bearer ${data.vault_kv_secret_v2.name.data.personal}"
    "X-GitHub-Api-Version" = "2022-11-28"
  }
}

provider "http" {}

data "http" "runners" {
  url             = local.runners_api_url
  request_headers = local.headers
  lifecycle {
    postcondition {
      condition     = contains([200], self.status_code)
      error_message = "Error"
    }
  }
}

data "http" "runner_reg_token" {
  url             = "${local.runners_api_url}/registration-token"
  request_headers = local.headers
  method          = "POST"
  lifecycle {
    postcondition {
      condition     = contains([201, 204], self.status_code)
      error_message = tostring(self.response_body)
    }
  }
}

resource "vault_kv_secret_v2" "runner_registration_token" {
  mount = "kv"
  name  = "github_runner"
  # cas                 = 1
  # delete_all_versions = true
  data_json = data.http.runner_reg_token.response_body
  custom_metadata {
    data = {
      created_by = "Terraform"
    }
  }
}

resource "nomad_job" "runner" {
  jobspec = templatefile("github-runner.nomad.tpl", {
    token          = jsondecode(vault_kv_secret_v2.runner_registration_token.data_json).token,
    runner_version = "2.310.2",
    org_name       = var.org_name
  })
}

resource "github_actions_runner_group" "arm64" {
  allows_public_repositories = false
  name                       = "hashi-at-home"
  visibility                 = "private"
  # default                    = false
}
