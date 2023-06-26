variable "minio_storage_size"{
    description = "Size of the minio storage"
    type = number
    // default = 10737418204
    default = "10"
}

job "minio" {
  vault {
    policies = ["read-only"]
  }
  meta {
    auto-backup = true
    backup-schedule = "@daily"
    backup-target-db = "postgres"
  }
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    distinct_hosts = true
  }

  constraint {
    attribute = "${attr.unique.hostname}"
    value = "sense"
    operator = "=="
  }

  group "server-1" {
    network {
      port "api" {}

      port "console" {}

      port "broker" {}
    }

    task "server" {
      driver = "raw_exec"
      artifact {
        source = "https://dl.min.io/server/minio/release/linux-arm64/minio"
        destination = "${NOMAD_ALLOC_DIR}/minio"
        mode = "file"
        options {
          checksum = "sha256:8789568665b4deda376e52f19bc85ca847a8644564446780b948961a7d5655cf"
        }
      }

      config {
        command = "${NOMAD_ALLOC_DIR}/minio"
        args    = [
          "server",
          "--address=${NOMAD_ADDR_api}",
          "${MINIO_VOLUMES}",
          "--console-address=${NOMAD_ADDR_console}"
        ]
      }

      template {
        data = <<EOH
MINIO_ROOT_USER="{{ with secret "hashiatho.me-v2/minio" }} {{ ".Data.data.root_username" }}{{ end }}"
MINIO_ROOT_PASSWORD="{{ with secret "hashiatho.me-v2/minio" }} {{ ".Data.data.root_password" }}{{ end }}"
        EOH
        destination = "secrets/config.env"
        env = true
      }

      env {
        MINIO_SERVER_URL="http://${NOMAD_ADDR_api}"
        MINIO_VOLUMES="http://${NOMAD_IP_api}/minio{1...4}"
        MINIO_DIRECTORIES="/minio{1...4}"
        MINIO_OPTS="--address ${NOMAD_ADDR_api} --console-address ${NOMAD_ADDR_console}"
        // MINIO_NOTIFY_REDIS_ENABLE_PRIMARY = "on"
        // MINIO_NOTIFY_REDIS_REDIS_ADDRESS_PRIMARY = "http://redis-cache.service.consul:6379"
        // MINIO_NOTIFY_REDIS_KEY_PRIMARY="bucketevents"
        // MINIO_NOTIFY_REDIS_FORMAT_PRIMARY="namespace"
        // MINIO_NOTIFY_REDIS_ENABLE_SECONDARY="on"
        // MINIO_NOTIFY_REDIS_REDIS_ADDRESS_SECONDARY="https://redis-cache.service.consul:6379"
        // MINIO_NOTIFY_REDIS_KEY_SECONDARY="bucketevents"
        // MINIO_NOTIFY_REDIS_FORMAT_SECONDARY="namespace"
      }

      resources {
        cpu = 1200
        memory = 512
      }

      constraint {
        attribute = "${attr.unique.storage.bytesfree}"
        operator = ">="
        value = "${var.minio_storage_size}"
      }

      service {
        tags = ["minio", "s3", "api", "urlprefix-/buckets"]
        port = "api"
        name = "minio-api"
        check {
          name     = "mino-healthy"
          type     = "http"
          port     = "api"
          method   = "GET"
          interval = "60s"
          timeout  = "5s"
          path     = "/minio/health/live"

          check_restart {
            limit = 2
            grace = "10s"
          }
        }
      }

      service {
        tags = ["minio", "s3", "console", "urlprefix-/minio-console redirect=9001,http://console.minio-console.service.consul"]
        port = "console"
        name = "minio-console"
        check {
          name     = "console-ready"
          type     = "tcp"
          port     = "console"
          interval = "60s"
          timeout  = "5s"
        }
      }
    }
  }
}
