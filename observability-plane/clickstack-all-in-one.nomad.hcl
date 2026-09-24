job "clickstack-ao1" {
  group "ai1" {
    network {
      port "http" {
        to = 8080
      }
      port "otlp-http" {
        to = 4318
      }
      port "otlp-grpc" {
        to = 4317
      }
    }
    task "clickstack" {
      resources {
        cpu    = 1024
        memory = 2048
      }
      driver = "docker"
      config {
        image = "clickhouse/clickstack-all-in-one:latest"
        ports = ["http", "otlp-http", "otlp-grpc"]
      }
      env {
        HYPERDX_APP_URL = "http://${NOMAD_IP_http}"
      }

      service {
        name = "otelexporter"
        port = "otlp-http"
        check {
          type     = "tcp"
          interval = "30s"
          timeout  = "10s"
        }
      }
    }
  }
}
