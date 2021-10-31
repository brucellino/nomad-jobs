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

    network {
      port "api" {
        static = 9000
      }

      port "console" {
        static = 38027
      }

      port "broker" {}
    }

    task "server" {
      driver = "raw_exec"

      resources {
        cores  = 1
        memory = 512
      }

      config {
        command = "minio"
        args    = ["server", "${attr.unique.hostname}/mnt/minio"]
      }

      env {
        MINIO_ROOT_USER     = var.root_username
        MINIO_ROOT_PASSWORD = var.root_password
        MINIO_ACCESS_KEY    = var.access_key
        MINIO_SECRET_KEY    = var.secret_key
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
            limit = 3
            grace = "10s"
          }
        }
      }
    }
  }
}
