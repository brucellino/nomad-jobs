# Define the required providers for this workload.
# We store the state in a Consul cluster.check
# We create resources in Github and Nomad, which need authentication tokens.
# The tokens are stored in Vault, which implies the use of the Vault provider.
#
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

variable "orgs" {
  description = "Names of the Github organisations"
  default     = ["AAROC", "Hashi-at-Home", "SouthAfricaDigitalScience"]
  sensitive   = false
  type        = set(string)
}

#
provider "vault" {}

provider "nomad" {}

data "vault_kv_secret_v2" "name" {
  mount = "kv"
  name  = "github"
}

provider "github" {
  token = data.vault_kv_secret_v2.name.data.org_scope
}

data "github_organization" "selected" {
  for_each = var.orgs
  name     = each.value
}

locals {
  # runners_api_url = "https://api.github.com/orgs/${var.org_name}/actions/runners"
  headers = {
    "Accept"               = "application/vnd.github+json"
    "Authorization"        = "Bearer ${data.vault_kv_secret_v2.name.data.org_scope}"
    "X-GitHub-Api-Version" = "2022-11-28"
  }
}

provider "http" {}

data "http" "runners" {
  for_each        = data.github_organization.selected
  url             = "https://api.github.com/orgs/${each.value.orgname}/actions/runners"
  request_headers = local.headers
  lifecycle {
    postcondition {
      condition     = contains([200], self.status_code)
      error_message = "Error"
    }
  }
}


output "runner_urls" {
  value = [for e in data.github_organization.selected : "https://api.github.com/orgs/${e.orgname}/actions/runners"]
}

data "http" "runner_reg_token" {
  for_each = data.github_organization.selected
  # url             = "${local.runners_api_url}/registration-token"
  url             = "https://api.github.com/orgs/${each.value.orgname}/actions/runners/registration-token"
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
  for_each = data.http.runner_reg_token

  mount = "kv"
  name  = "github_runner/${each.key}"
  # cas                 = 1
  # delete_all_versions = true
  data_json = each.value.body
  custom_metadata {
    data = {
      created_by = "Terraform"
    }
  }
}

resource "nomad_job" "runner" {
  for_each = data.github_organization.selected
  jobspec = templatefile("github-runner.nomad.tpl", {
    token          = jsondecode(vault_kv_secret_v2.runner_registration_token[each.key].data_json).token,
    runner_version = "2.310.2",
    org            = each.key
  })
}