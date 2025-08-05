# Nomad job to run Loki server
job "loki" {
  group "loki" {
    vault {}
    network {
      port "http" {
        to = 3100
      }
    }
    service {
      name = "loki"
      port = "http"
      tags = ["loki"]
      check {
        name     = "loki-ready"
        type     = "http"
        path     = "/ready"
        interval = "10s"
        timeout  = "2s"
      }

      check {
        name     = "loki-metrics"
        type     = "http"
        path     = "/metrics"
        interval = "10s"
        timeout  = "2s"
      }
    }
    task "server" {
      driver = "docker"
      config {
        image = "grafana/loki:3.5.3"
        ports = ["http"]
        args = [
          "--config.file=/local/loki-config.yaml",
          "--log.level=info",
          "--log.format=json",
        ]
      }
      template {
        data        = <<EOF
{{ with secret "hashiatho.me-v2/data/loki_logs_bucket" }}
auth_enabled: false

server:
  http_listen_port: 3100

common:
  ring:
    instance_addr: 0.0.0.0
    kvstore:
      store: inmemory
  replication_factor: 1
  path_prefix: /loki

schema_config:
  configs:
  - from: 2020-05-15
    store: tsdb
    object_store: s3
    schema: v13
    index:
      prefix: index_
      period: 24h

storage_config:
  tsdb_shipper:
    active_index_directory: /loki/index
    cache_location: /loki/index_cache
  aws:
    region: eeur
    bucketnames: hah-logs
    endpoint: https://beb61125927ff6f81b508dec6fdfdfa2.r2.cloudflarestorage.com
    access_key_id: {{ .Data.data.access_key_id }}
    secret_access_key: {{ .Data.data.secret_access_key }}
    s3forcepathstyle: true
{{ end }}
        EOF
        destination = "local/loki-config.yaml"
        change_mode = "restart"
        wait = {
          min = "1m"
          max = "10m"
        }
        splay = "30s"
      }

    }
  }
}
