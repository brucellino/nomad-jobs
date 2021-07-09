job "vault-dev" {
  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "sense.station"
    operator  = "!="
  }

  datacenters = ["dc1"]
  type        = "service"

  group "server" {
    count = 3

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

      artifact {
        source      = "https://releases.hashicorp.com/vault/1.7.3/vault_1.7.3_linux_arm64.zip"
        destination = "local/vault"
        mode        = "file"
      }

      template {
        data = <<EOH
listener "tcp" {
  address = "0.0.0.0:8200"
  tls_disable = true
}
api_addr = "http://127.0.0.1:8200"
cluster_addr = "http://127.0.0.1:8201"

storage "raft" {
  path = "{{ env "NOMAD_ALLOC_DIR" }}/raft"
  node_id = "${attr.unique.hostname}"
}
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
EOH

        destination = "local/vault.d/vault.hcl"
      }

      config {
        command = "local/vault"
        args    = ["server", "-config=local/vault.d/vault.hcl"]
      }
    }
  }
}
