variable "root_username" {
    description = "Username which will be assigned root user privileges"
    type = string
}

variable "root_password" {
    description = "Password for the root user"
    type = string
}

variable "minio_storage_size"{
    description = "Size of the minio storage"
    type = number
    default = 10737418204
}

job "minio" {

  // vault {
  //   policies = ["default"]
  // }
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
    attribute = "${attr.cpu.arch}"
    value     = "arm64"
  }

  constraint {
    attribute = "${attr.unique.hostname}"
    operator = "regexp"
    value = "^turing[1|2|3|4]"
  }

  group "server" {
    count = 4
    update {
      max_parallel = 4
      health_check = "checks"
      canary = 4
      auto_promote = true
      auto_revert = true
    }
    reschedule {
      attempts       = 1
      interval       = "10m"
      unlimited      = false
      delay          = "5s"
      delay_function = "constant"
    }

    migrate {
      max_parallel = 4
      health_check = "checks"
      min_healthy_time = "10s"
      healthy_deadline = "10s"
    }

    volume "buckets" {
      type = "host"
      source=  "scratch"
      read_only = false
    }

    network {
      port "api" {
        static = 9000
      }

      port "console" {
        static = 9001
      }

      port "broker" {}
    }

    task "server" {
      driver = "exec"
      artifact {
        source = "https://dl.min.io/server/minio/release/linux-${attr.cpu.arch}/minio"
        destination = "${NOMAD_ALLOC_DIR}/minio"
        mode = "file"
        options {
          checksum = "sha256:9030f852c47fc37d56e5ef13475c09aa1c4725e4ca5dffa9803809969c05214e"
        }
      }

      config {
        command = "${NOMAD_ALLOC_DIR}/minio"
        args    = [
          "server",
          "http://turing{1...4}.node.consul/data/nomad"
          // "--address=${NOMAD_ADDR_api}",
          // "--console-address=${NOMAD_ADDR_console}"
        ]
      }
      volume_mount {
        volume      = "buckets"
        destination = "${NOMAD_ALLOC_DIR}/data"
      }

      env {
        MINIO_ROOT_USER     = var.root_username
        MINIO_ROOT_PASSWORD = var.root_password
        // MINIO_ROOT_PASSWORD =
        MINIO_SERVER_URL    = "http://${NOMAD_ADDR_api}"
        // MINIO_VOLUMES="http://${attr.unique.hostname}/${NOMAD_ALLOC_DIR}/data"
        MINIO_NOTIFY_REDIS_ENABLE_PRIMARY = "on"
        MINIO_NOTIFY_REDIS_REDIS_ADDRESS_PRIMARY = "http://redis-cache.service.consul:6379"
        MINIO_NOTIFY_REDIS_KEY_PRIMARY="bucketevents"
        MINIO_NOTIFY_REDIS_FORMAT_PRIMARY="namespace"
        MINIO_NOTIFY_REDIS_ENABLE_SECONDARY="on"
        MINIO_NOTIFY_REDIS_REDIS_ADDRESS_SECONDARY="https://redis-cache.service.consul:6379"
        MINIO_NOTIFY_REDIS_KEY_SECONDARY="bucketevents"
        MINIO_NOTIFY_REDIS_FORMAT_SECONDARY="namespace"
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
