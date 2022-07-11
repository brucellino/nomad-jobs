variable "access_key" {
  type = string
}

variable "secret_key" {
  type = string
}

variable "loki_version" {
  type = string
  default = "v2.6.0"
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
    max_parallel = 1
    health_check = "checks"
    min_healthy_time = "5s"
    healthy_deadline = "300s"
    progress_deadline = "10m"
    auto_revert = true
    auto_promote = true
    canary = 1
  }
  priority = 80
  group "log-server" {
    count = 1

    network {
      port "http" {
        static = 3100
      }
      port "grpc" {
        static = 9096
      }
    }
    service {
      name = "loki-http-server"
      tags = ["logs", "loki", "observability", "urlprefix-/loki"]
      port = "http"
      on_update = "require_healthy"

      check {
        name = "loki_alive"
        type = "grpc"
        port = "grpc"
        interval = "10s"
        timeout = "3s"
      }

      check {
        name = "loki_ready"
        type = "http"
        path = "/ready"
        port = "http"
        interval = "10s"
        timeout = "3s"
      }
    }
    task "server" {
      driver = "exec"
      env {
        access_key = var.access_key
        secret_key = var.secret_key
      }
      config {
        command = "loki"
        args = [
          "-config.file=local/loki.yml"
        ]
      }
      resources {
        cpu = 128
        memory = 200
      }
      template {
        data = file("loki.yml.tpl")
        destination = "local/loki.yml"
        change_mode = "restart"
      }
      artifact {
        source = "https://github.com/grafana/loki/releases/download/${var.loki_version}/loki-linux-${attr.cpu.arch}.zip"
        options { # checksum depends on the cpu arch
        }
        destination = "local/loki"
        mode = "file"
      }
    }
  }
}
