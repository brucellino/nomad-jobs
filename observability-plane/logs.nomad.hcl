# All in one deployment for Clickstack
job "logs" {
  group "clickstack" {
    network {
      port "ui" {
        to = 8080
      }
      port "api" {
        to = 8000
      }
      port "opamp" {
        to = 4320
      }
      port "otlp_grpc" {
        to = 4317
      }
      port "otlp_http" {
        to = 4318
      }
      port "otel_health" {
        to = 13133
      }
      port "otel_metrics" {
        to = 8888
      }
      port "clickhouse" {
        to = 8123
      }
    }

    volume "db" {
      type   = "host"
      source = "clickhouse-db"
    }

    volume "data" {
      type   = "host"
      source = "clickhouse-data"
    }

    task "ai1" {
      resources {
        cpu    = 2048
        memory = 2048
      }
      service {
        port = "ui"
        check {
          type     = "http"
          path     = "/api/health"
          port     = "ui"
          interval = "10s"
          timeout  = "2s"
        }
      }

      service {
        port = "otlp_http"
        check {
          type     = "http"
          path     = "/"
          port     = "otlp_http"
          interval = "10s"
          timeout  = "2s"
        }
      }

      service {
        port = "otlp_grpc"
        check {
          type     = "tcp"
          port     = "otlp_grpc"
          interval = "10s"
          timeout  = "2s"
        }
      }
      shutdown_delay = "15s"
      driver         = "docker"
      config {
        image = "clickhouse/clickstack-all-in-one:latest"
        ports = [
          "ui",
          "otlp_grpc",
          "otlp_http",
          "clickhouse",
          "otel_health",
          "otel_metrics",
          "opamp",
          "api",
        ]
      }
      volume_mount {
        volume      = "db"
        destination = "/data/db"
        read_only   = false
      }
      volume_mount {
        volume      = "data"
        destination = "/var/lib/clickhouse"
        read_only   = false
      }
      env {
        # HYPERDX_API_PORT = 8080
        HYPERDX_APP_URL = "http://${NOMAD_IP_ui}"
      }
    }
  }
}
