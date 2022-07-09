variable "loki_version" {
  type = string
  default = "v2.6.0"
  description = "Loki release to deploy. See https://github.com/grafana/loki/releases/"
}

variable "access_key" {
  type = string
  description = "S3 compatible storage access key ID"
}

variable "secret_key" {
  type = string
  description = "S3 compatible storage secret key"
}

variable "logs_bucket" {
  type = string
  description = "name of  the bucket we will store loki logs in"
}

variable "s3_endpoint" {
  type = string
  description = "endpoint of the s3-compatible storage backend for the logs"
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
    healthy_deadline = "60s"
    progress_deadline = "3m"
    auto_revert = true
    auto_promote = true
    canary = 1
  }
  priority = 80
  group "log-server" {
    count = 1

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
        memory = 200
      }
      template {
        // source = "local/loki.yml.tpl"
        data = <<EOT
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096
memberlist:
  join_members:
    - loki-http-server
schema_config:
  configs:
    - from: 2022-01-01
      store: boltdb-shipper
      object_store: s3
      schema: v11
      index:
        prefix: index_
        period: 24h
common:
  path_prefix: local/
  replication_factor: 1
  storage:
    s3:
      endpoint: ${var.s3_endpoint}
      bucketnames: ${var.logs_bucket}
      access_key_id: ${var.access_key}
      secret_access_key: ${var.secret_key}
      s3forcepathstyle: true
  ring:
    kvstore:
      store: consul
ruler:
  storage:
    s3:
      bucketnames: hah-logs
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
    }

  }
}
