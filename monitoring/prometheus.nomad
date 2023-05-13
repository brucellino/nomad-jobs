variable "prom_version" {
  default = "2.43.0"
  type = string
  description = "Version of prometheus to use"
}

variable "prom_sha2" {
  type = string
  default = "79c4262a27495e5dff45a2ce85495be2394d3eecd51f0366c706f6c9c729f672" #pragma: allowlist secret
  description = "https://prometheus.io/download/"
}

job "prometheus" {
  datacenters = ["dc1"]
  type        = "service"
  meta {
    auto-backup = true
    backup-schedule = "@daily"
    backup-target-db = "postgres"
  }
  update {
    max_parallel = 2
    health_check = "checks"
    canary = 1
    auto_promote = true
    auto_revert = true
  }

  constraint {
     attribute = attr.cpu.arch
     value     = "arm64"
  }

  group "server" {
    count = 1
    volume "data" {
      type      = "host"
      read_only = false
      source    = "scratch"
    }
    network {
      port "prometheus_ui" {}
    }

    restart {
      attempts = 1
      interval = "7m"
      delay    = "1m"
      mode     = "fail"
    }

    ephemeral_disk {
      size = 300
    }

    task "prometheus" {
      artifact {
        source      = "https://github.com/prometheus/prometheus/releases/download/v${var.prom_version}/prometheus-${var.prom_version}.linux-arm64.tar.gz"
        destination = "local"

        options {
          checksum = "sha256:${var.prom_sha2}"
        }
      }
      template {
        change_mode = "signal"
        change_signal = "SIGHUP"
        destination = "local/prometheus.yml"
        source = file("templates/prometheus.yml.tpl")
        wait {
          min = "10s"
          max = "20s"
        }
      }

      template {
        change_mode = "noop"
        destination = "local/node-rules.yml"
        left_delimiter = "[["
        right_delimiter = "]]"
        wait {
          min = "10s"
          max = "20s"
        }
        source = file("templates/node-rules.yml.tpl")
      }
      driver = "exec"

      config {
        command = "local/prometheus-${var.prom_version}.linux-arm64/prometheus"
        args    = [
          "--config.file=local/prometheus.yml",
          "--storage.tsdb.retention.size=1GB",
          "--storage.tsdb.retention.time=7d",
          "--web.listen-address=:${NOMAD_PORT_prometheus_ui}",
          "--web.enable-admin-api",
          "--storage.tsdb.path=data"
        ]
      }
      volume_mount {
        volume      = "data"
        destination = "data"
        read_only   = false
      }
      resources {
        cpu = 250
        memory = 400
      }

      service {
        name = "prometheus"
        tags = ["urlprefix-/prometheus"]
        port = "prometheus_ui"

        check {
          name     = "prometheus_readiness check"
          type     = "http"
          path     = "/-/ready"
          interval = "10s"
          timeout  = "2s"
        }
        check {
          name     = "prometheus healthiness check"
          type     = "http"
          path     = "/-/healthy"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
