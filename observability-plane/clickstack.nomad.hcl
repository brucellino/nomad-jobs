# Used by docker-compose.yml
variable "HDX_IMAGE_REPO" {
  type    = string
  default = "docker.hyperdx.io"
}
variable "CH_IMAGE_REPO" {
  type    = string
  default = "docker.clickhouse.com"
}

variable "IMAGE_NAME_DOCKERHUB" {
  type    = string
  default = "hyperdx/hyperdx"
}
variable "NEXT_LOCAL_IMAGE_NAME_DOCKERHUB" {
  type    = string
  default = "clickhouse/clickstack-local"
}
variable "LOCAL_IMAGE_NAME_DOCKERHUB" {
  type    = string
  default = "hyperdx/hyperdx-local"
}
variable "NEXT_ALL_IN_ONE_IMAGE_NAME_DOCKERHUB" {
  type    = string
  default = "clickhouse/clickstack-all-in-one"
}
variable "ALL_IN_ONE_IMAGE_NAME_DOCKERHUB" {
  type    = string
  default = "hyperdx/hyperdx-all-in-one"
}
variable "NEXT_OTEL_COLLECTOR_IMAGE_NAME_DOCKERHUB" {
  type    = string
  default = "clickhouse/clickstack-otel-collector"
}
variable "OTEL_COLLECTOR_IMAGE_NAME_DOCKERHUB" {
  type    = string
  default = "hyperdx/hyperdx-otel-collector"
}
variable "CODE_VERSION" {
  type    = string
  default = "2.19.0"
}
variable "IMAGE_VERSION_SUB_TAG" {
  type    = string
  default = ".19.0"
}
variable "IMAGE_VERSION" {
  type    = string
  default = "2"
}
variable "IMAGE_NIGHTLY_TAG" {
  type    = string
  default = "2-nightly"
}
variable "IMAGE_LATEST_TAG" {
  type    = string
  default = "latest"
}

# Set up domain URLs
# HYPERDX_API_PORT=8000 #optional (should not be taken by other services)
# HYPERDX_APP_PORT=8080
# HYPERDX_APP_URL=http://localhost
# HYPERDX_LOG_LEVEL=debug
# HYPERDX_OPAMP_PORT=4320
# HYPERDX_BASE_PATH=

# # Otel/Clickhouse config
# HYPERDX_OTEL_EXPORTER_CLICKHOUSE_DATABASE=default
job "clickstack" {
  group "all" {
    network {
      port {
        otelhealth {
          to = 13133
        }
        otlp_grpc {
          to = 4317
        }
        otlp_http {
          to = 4318
        }
        metrics {
          to = 8888
        }
      }
    }

    task "db" {
      image = "mongo:5.0.32-focal"
      # Needs a volume
    }
    # task "otel-collector" {
    #   driver = "docker"
    #   config {
    #     image = "${var.CH_IMAGE_REPO}/${var.NEXT_OTEL_COLLECTOR_IMAGE_NAME_DOCKERHUB}:${var.IMAGE_VERSION}"
    #   }
    #   env {
    #     CLICKHOUSE_ENDPOINT = "${NOMAD_ADDR_server}"
    #   }
    # }
  }
}
