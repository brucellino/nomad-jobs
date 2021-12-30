job "vault-dev" {
  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "sense.station"
    operator  = "!="
  }

  datacenters = ["dc1"]
  type        = "service"

  group "server" {
    count = 5

    network {
      port "api" {
        static = 8200
      }
    }

    task "init" {
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      driver = "raw_exec"

      config {
        command = "mkdir"
        args    = ["-vp", "${NOMAD_ALLOC_DIR}/raft"]
      }
    }

    task "server" {
      driver = "raw_exec"

      constraint {
        attribute = "${attr.cpu.arch}"
        value     = "arm64"
      }

      resources {
        cpu    = 1000
        memory = 512
      }

      artifact {
        source      = "https://releases.hashicorp.com/vault/1.9.2/vault_1.9.2_linux_arm64.zip"
        destination = "local/vault"
        mode        = "file"
      }

      template {
        // source = "vault.hcl.tmpl"
        data = <<EOT
listener "tcp" {
  address = "{{ env "attr.unique.network.ip-address" }}:8200"
  tls_disable = true
}
api_addr = "http://{{ env "attr.unique.network.ip-address" }}:8200"
cluster_addr = "http://{{ env "attr.unique.network.ip-address" }}:8201"

storage "raft" {
  path = "{{ env "NOMAD_ALLOC_DIR" }}/raft/"
  node_id = "{{ env "attr.unique.hostname" }}"

}

disable_mlock = true
cluster_name = "hah"

telemetry {
  disable_hostname = false
  prometheus_retention_time = "30s"
}

service_registration "consul" {
  address = "127.0.0.1:8500"
  service = "vault-dev"
  service_tags = "dev"
}

ui = true
log_format = "json"

EOT

        destination = "local/vault.d/vault.hcl"
      }

      config {
        command = "local/vault"
        args    = ["server", "-config=local/vault.d/vault.hcl"]
      }
    }
  }
}
