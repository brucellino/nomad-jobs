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
    count = 3

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
      resources {
        cpu = 128
        memory = 50
      }
      template {
        // source = "local/loki.yml.tpl"
        data = <<EOT
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096
ingester:
  autoforget_unhealthy: true
  lifecycler:
    heartbeat_period: "15s"
    min_ready_duration: "30s"
ingester_client:
  pool_config:
    health_check_ingesters: true
  remote_timeout: "5s"
common:
  replication_factor: 3
  path_prefix: /tmp/loki
  storage:
    filesystem:
#      directory: /tmp/loki
      chunks_directory: /tmp/loki/chunks
      rules_directory: /tmp/loki/rules
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: consul

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

ruler:
  alertmanager_url: http://localhost:9093

analytics:
  reporting_enabled: false
        EOT
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
