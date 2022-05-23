variable "loki_version" {
  type = string
  default = "v2.5.0"
  description = "Loki release to deploy. See https://github.com/grafana/loki/releases/"
}
job "loki" {
  datacenters = ["dc1"]
  type = "service"
  name = "loki"
  // migrate {}
  meta {
    auto-backup = true
    backup-schedule = "@hourly"
    backup-target-db = "postgres"
  }
  update {
    max_parallel = 2
    health_check = "checks"
    min_healthy_time = "5s"
    healthy_deadline = "60s"
    progress_deadline = "3m"
    auto_revert = true
    auto_promote = true
    canary = 1
  }
  priority = 80
  group "log-server" {
    count = 2

    network {
      port "loki_http_listen" {
        static = 3100
      }
      port "loki_grpc_listen" {
        static = 9096
      }
    }
    service {
      name = "loki-http-server"
      tags = ["logs", "loki", "observability", "urlprefix-/loki"]
      port = "loki_http_listen"

      check {
        name = "loki_http_alive"
        type = "tcp"
        interval = "10s"
        timeout = "3s"
      }

      check {
        name = "loki_http_ready"
        type = "http"
        path = "/ready"
        port = "loki_http_listen"
        interval = "10s"
        timeout = "3s"
      }
    }
    task "server" {
      driver = "raw_exec"
      config {
        command = "loki"
        args = [
          "-config.file=local/loki.yml"
        ]
      }
      template {
        source = "local/loki.yml.tpl"
        destination = "local/loki.yml"
      }
      artifact {
        source = "https://github.com/grafana/loki/releases/download/${var.loki_version}/loki-linux-${attr.cpu.arch}.zip"
        options { # checksum depends on the cpu arch
        }
        destination = "local/loki"
        mode = "file"
      }
      // artifact {
      //   source = "http://minio-deploy-run.service.consul:9000/loki-bin/loki-linux-${attr.cpu.arch}.zip"
      //   destination = "local/loki"
      //   mode = "file"
      // }
      // artifact {
      //   source = "http://minio-deploy-run.service.consul:9000/loki-config/loki.hcl.tpl"
      //   destination = "local/loki.yml.tpl"
      //   mode = "file"
      // }

    }

  }
}
