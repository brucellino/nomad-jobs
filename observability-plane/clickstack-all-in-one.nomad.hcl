job "clickstack-ao1" {
  group "ai1" {
    network {
      port "ui" {
        to = 8080
      }
      port "otlp_grpc" {
        to = 4317
      }
      port "otlp_http" {
        to = 4318
      }
      port "clickhouse" {
        to = 8123
      }
    }

    task "clickstack" {
      resources {
        cores  = 4
        memory = 4096
      }
      driver = "docker"
      config {
        image = "clickhouse/clickstack-all-in-one:latest"
        ports = ["ui", "otlp_grpc", "otlp_http", "clickhouse"]
      }
      env {
        # HYPERDX_API_PORT = 8000
        HYPERDX_APP_URL = "http://${NOMAD_IP_ui}"
      }
    }
  }
}
