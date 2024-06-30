# A job to retrieve a consul token from Vault.
job "consul-backup" {
  datacenters = ["dc1"]
  type        = "batch"
  periodic {
    crons            = ["1-59/15 * * * * *"]
    prohibit_overlap = false
  }
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
env
source ${NOMAD_SECRETS_DIR}/env
env
echo "Hi there! I'm a dufus"
# Lookup vault token
curl -v -X GET -H "X-Consul-Token: ${CONSUL_HTTP_TOKEN}" http://localhost:8500/v1/snapshot > ${NOMAD_ALLOC_DIR}/data/snapshot
# Get the playbook
curl -X GET \
  -H "Accept: applicaton/vnd.github+json" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "X-Github-Api-Version: 2022-11-28" \
  https://api.github.com/repos/brucellino/personal-automation/contents/playbooks/backup-state.yml > playbook.yml
ls -lht
        EOH
        destination = "local/start.sh"
        perms       = "777"
      }
      template {
        data        = <<-EOH
CONSUL_HTTP_TOKEN="{{ with secret "hashi_at_home/creds/cluster-role" }}{{ .Data.token }}{{ end }}"
GITHUB_TOKEN="{{ with secret "/github_personal_tokens/token"  "repositories=personal-automation"
"installation_id=44668070"}}{{ .Data.token }}{{ end }}"
NOMAD_ADDR={{ with service "http.nomad" }}{{ with index . 0 }}http://{{ .Address }}:{{ .Port }}{{ end }}{{ end }}
VAULT_ADDR={{ range service "vault" }}http://{{ .Address }}:{{ .Port }}{{- end }}
      EOH
        destination = "${NOMAD_SECRETS_DIR}/env"
        perms       = "400"
        env         = true
      }
      driver = "exec"
      config {
        command = "local/start.sh"
      }
    }
  }
}
