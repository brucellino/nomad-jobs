# A job to retrieve a consul token from Vault.
job "hah-state-backup" {
  datacenters = ["dc1"]
  type        = "batch"
  priority    = 75
  namespace   = "ops"
  periodic {
    crons            = ["0 */6 * * * *"]
    prohibit_overlap = false
  }
  group "all" {
    count = 1
    network {}
    vault {
      env = true
    }
    restart {
      attempts = 0
    }
    task "snapshot" {
      resources {
        cpu    = 1000
        memory = 1024
      }
      # Get a vault token so that we can read consul creds
      template {
        data        = <<-EOH
#!/bin/env bash
PATH=${HOME}/.local/bin:${PATH}
source ${NOMAD_SECRETS_DIR}/env
echo Nomad addr: ${NOMAD_ADDR}
# Generate Consul Snapshot
curl -v \
  -X GET \
  -H "X-Consul-Token: ${CONSUL_HTTP_TOKEN}" \
  http://localhost:8500/v1/snapshot \
  > ${NOMAD_ALLOC_DIR}/data/consul_$(date --iso-8601=date).snap

# Generate Nomad snapshot
curl -v \
  -X GET \
  -H "X-Nomad-Token: ${NOMAD_TOKEN}" \
  ${NOMAD_ADDR}/v1/operator/snapshot \
  > ${NOMAD_ALLOC_DIR}/data/nomad_$(date --iso-8601=date).snap

# Get the playbook
curl -X GET \
  -H "Accept: applicaton/vnd.github+json" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "X-Github-Api-Version: 2022-11-28" \
  https://api.github.com/repos/brucellino/personal-automation/contents/playbooks/backup-state.yml \
  | jq -r .content \
  | base64 -d > playbook.yml
virtualenv /local/execute
source /local/execute/bin/activate
pip install ansible boto3 botocore hvac
which python3
which ansible
which ansible-playbook
ansible-playbook -c local -i localhost, playbook.yml
        EOH
        destination = "local/start.sh"
        perms       = "777"
      }
      template {
        data        = <<-EOH
ANSIBLE_PYTHON_INTERPRETER=/local/execute/bin/python3
CONSUL_HTTP_TOKEN="{{ with secret "hashi_at_home/creds/cluster-role" }}{{ .Data.token }}{{ end }}"
CONSUL_HTTP_ADDR=http://localhost:8500
GITHUB_TOKEN="{{ with secret "github/token" "repositories=personal-automation"
"installation_id=17687806"}}{{ .Data.token }}{{ end }}"
NOMAD_ADDR={{ with service "http.nomad" }}{{ with index . 0 }}http://{{ .Address }}:{{ .Port }}{{ end }}{{ end }}
NOMAD_TOKEN="{{ with secret "nomad/creds/mgmt" }}{{ .Data.secret_id }}{{ end }}"
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
