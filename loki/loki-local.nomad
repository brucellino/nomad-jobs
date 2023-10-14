// variable "access_key" {
//   type = string
// }

// variable "secret_key" {
//   type = string
// }

variable "loki_version" {
  type = string
  default = "v2.9.1"
}

job "loki" {
  datacenters = ["dc1"]
  type = "service"
  name = "loki"

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
      tags = [
        "urlprefix-/loki strip=/loki",
        "traefik.enable=true",
        "traefik.http.routers.http.rule=Path(`loki`)"
        ]
      port = "http"
      on_update = "require_healthy"

      check {
        name = "loki_ready"
        type = "http"
        path = "/ready"
        port = "http"
        interval = "10s"
        timeout = "3s"
      }
    }

    service {
      name = "loki-grpc"
      port = "grpc"
    }

    task "server" {
      driver = "exec"
      // env {
      //   access_key = var.access_key
      //   secret_key = var.secret_key
      // }
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
        data = <<EOH
---
auth_enabled: false

server:
  http_listen_port: {{ env "NOMAD_HOST_PORT_http" }}
  grpc_listen_port: {{ env "NOMAD_HOST_PORT_grpc" }}
  register_instrumentation: true
distributor:
  ring:
    kvstore:
      store: consul
      prefix: loki/collectors/
      consul:
        host: http://localhost:8500
ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s
  chunk_idle_period: 5m
  chunk_retain_period: 30s

schema_config:
  configs:
  - from: 2020-05-15
    store: boltdb
    object_store: filesystem
    schema: v11
    index:
      prefix: index_
      period: 168h

storage_config:
  boltdb:
    directory: /tmp/loki/index

  filesystem:
    directory: /tmp/loki/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h
EOH
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
