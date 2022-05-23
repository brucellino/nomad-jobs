variable "root_username" {
    description = "Username which will be assigned root user privileges"
    type = string
}

variable "root_password" {
    description = "Password for the root user"
    type = string
}

variable "access_key" {
    description = "Access key for the root user"
    type = string
}

variable "secret_key" {
    description = "Secret key for the root user"
    type = string
}

variable "minio_storage_size"{
    description = "Size of the minio storage"
    type = number
    default = 10737418204
}

job "minio" {
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

  group "server" {
    count = 1
    update {
      max_parallel = 1
      health_check = "checks"
      canary = 1
      auto_promote = true
      auto_revert = true
    }
    reschedule {
      attempts       = 1
      interval       = "24h"
      unlimited      = false
      delay          = "5s"
      delay_function = "constant"
    }

    migrate {
      max_parallel = 1
      health_check = "checks"
      min_healthy_time = "10s"
      healthy_deadline = "10s"
    }

    volume "buckets" {
      type = "host"
      source=  "scratch"
      read_only = false
    }
    restart {

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
        // options {
        //   checksum = "sha256:665f6690b630a7f7f5326dd3cbbf0647bbbc14c4a6cadbe7dfc919a23d727d56"
        // }
      }
      config {
        command = "${NOMAD_ALLOC_DIR}/minio"
        args    = [
          "server",
          "--console-address=${NOMAD_ADDR_console}",
          "${NOMAD_ALLOC_DIR}/data"]
      }
      volume_mount {
        volume      = "buckets"
        destination = "${NOMAD_ALLOC_DIR}/data"
      }

      env {
        MINIO_ROOT_USER     = var.root_username
        MINIO_ROOT_PASSWORD = var.root_password
        MINIO_VOLUMES="http://${attr.unique.hostname}/${NOMAD_ALLOC_DIR}/data"
        MINIO_ACCESS_KEY    = var.access_key
        MINIO_SECRET_KEY    = var.secret_key
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
        tags = ["minio", "s3", "console", "urlprefix-/minio-console"]
        port = "console"
        name = "minio-console"
        check {
          name     = "console-ready"
          type     = "tcp"
          port     = "console"
          interval = "60s"
          timeout  = "5s"

        //   check_restart {
        //     limit = 2
        //     grace = "10s"
        //   }
        }
      }
    }
  }
}
