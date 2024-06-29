# A job to retrieve a consul token from Vault.
job "consul-backup" {
  datacenters = ["dc1"]
  type        = "batch"
  // periodic {
  //   crons = ["1-59/15 * * * * *"]
  //       prohibit_overlap = false
  // }
  group "data" {
    count = 1
    network {}
    vault {
      env = true
    }
    restart {
      attempts = 0
    }

    task "check-consul" {
      # Get a vault token so that we can read consul creds
      template {
        data        = <<-EOH
#!/bin/env bash
echo "Hi there! I'm a dufus"
# Lookup vault token
curl -H "X-Vault-Token: ${VAULT_TOKEN}" \
     -X GET \
     http://active.vault.service.consul:8200/v1/auth/token/lookup-self > output.json
cat output.json | jq
sleep 120

        EOH
        destination = "local/start.sh"
        perms       = "777"
      }
      template {
        data        = <<-EOH
{{ with secret "hashi_at_home/creds/cluster-role" }}{{ .Data.token }}{{ end }}
      EOH
        destination = "local/consul_token"
        perms       = "400"
      }
      driver = "raw_exec"
      config {
        command = "local/start.sh"
      }
    }
  }
}
