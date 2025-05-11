# A job to retrieve a consul token from Vault.
job "hah-state-backup" {
  datacenters = ["dc1"]
  type        = "batch"
  priority    = 75
  namespace   = "ops"
  periodic {
    crons            = ["0 */6 * * * *"]
    prohibit_overlap = true
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
      artifact {
        source      = "https://downloads.rclone.org/v1.69.2/rclone-v1.69.2-linux-arm64.zip"
        destination = "/local"
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

# # Generate Vault snapshot
curl -v \
  -X GET \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  ${NOMAD_ADDR}/v1/operator/snapshot \
  > ${NOMAD_ALLOC_DIR}/data/nomad_$(date --iso-8601=date).snap

/local/rclone-v1.69.2-linux-arm64/rclone --config /local/rclone.conf copy ${NOMAD_ALLOC_DIR}/data/consul_$(date --iso-8601=date).snap r2:consul/
/local/rclone-v1.69.2-linux-arm64/rclone --config /local/rclone.conf copy ${NOMAD_ALLOC_DIR}/data/nomad_$(date --iso-8601=date).snap r2:nomad/
EOH
        destination = "local/start.sh"
        perms       = "777"
      }
      template {
        data        = <<-EOH
{{ with secret "cloudflare/data/hah_state_backup" }}
[r2]
type = s3
provider = Cloudflare
access_key_id = {{ .Data.data.access_key_id }}
secret_access_key = {{ .Data.data.secret_key }}
endpoint = {{ .Data.data.s3_endpoint }}/hah-snapshots
acl = private
{{ end }}
        EOH
        destination = "/local/rclone.conf"

      }
      template {
        data        = <<-EOH
CONSUL_HTTP_TOKEN="{{ with secret "hashi_at_home/creds/cluster-role" }}{{ .Data.token }}{{ end }}"
CONSUL_HTTP_ADDR=http://localhost:8500
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
