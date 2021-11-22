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

job "minio" {
  datacenters = ["dc1"]
  type        = "service"


  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "arm64"
  }

  group "deploy" {
    count = 4
    reschedule {
      attempts       = 1
      interval       = "24h"
      unlimited      = false
      delay          = "5s"
      delay_function = "constant"
    }

    migrate {
      max_parallel = 2
      health_check = "checks"
      min_healthy_time = "10s"
      healthy_deadline = "10s"

    }
    restart {

    }
    network {
      port "api" {
        static = 9000
      }

      port "console" {
        static = 38027
      }

      port "broker" {}
    }

    task "stage" {
      lifecycle {
        hook = "prestart"
        sidecar = false
      }
      driver = "raw_exec"

      artifact {
        source = "https://dl.min.io/server/minio/release/linux-arm64/minio"
        destination = "${NOMAD_ALLOC_DIR}/minio"
        mode = "file"
        options {
          checksum = "sha256:aa305e8147722b32873f6aa84ce9a5cce89746df893b530bb6c9fcefa4be8c2f"
        }
      }

      config {
        command = "chmod"
        args = ["+x", "${NOMAD_ALLOC_DIR}/minio"]

      }

      resources {
        cpu = 1
        memory = 512
      }
    }
    task "run" {
      driver = "raw_exec"
      config {
        command = "${NOMAD_ALLOC_DIR}/minio"
        args    = ["server", "${attr.unique.hostname}/mnt/minio"]
      }

      env {
        MINIO_ROOT_USER     = var.root_username
        MINIO_ROOT_PASSWORD = var.root_password
        // MINIO_ACCESS_KEY    = var.access_key
        // MINIO_SECRET_KEY    = var.secret_key
      }

      service {
        tags = ["minio", "s3", "api"]
        port = "api"

        check {
          name     = "node-liveness"
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
    }
  }
}
