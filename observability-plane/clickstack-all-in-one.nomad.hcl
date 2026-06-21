job "clickstack-all-in-one" {
  group "clickhouse" {
    constraint {
      attribute = "${attr.unique.hostname}"
      operator  = "regexp"
      value     = "ticklish|cape"
    }
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
      driver = "docker"
      resources {
        cpu    = 1024
        memory = 2048
      }
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
