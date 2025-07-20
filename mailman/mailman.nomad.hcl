# see https://github.com/maxking/docker-mailman/blob/main/docker-compose.yaml
variable "secret_key" {
  type = string
}
variable "hyperkitty_api_key" {
  type = string
}
variable "mailman_user" {
  type = string
}
variable "mailman_pass" {
  type = string
}


job "mailman" {
  type = "service"
  group "core" {
    network {
      port "postgres" {
        to = "5432"
      }
      port "mailman_http" {
        to = "8000"
      }
      port "mailman_usgi" {
        to = "8080"
      }
      port "mailman_api" {
        to = "8001"
      }
      port "mailman_lmtp" {
        to = "8024"
      }
    }
    task "database" {
      driver = "docker"
      env {
        POSTGRES_USER        = var.mailman_user
        POSTGRES_PASSWORD    = var.mailman_pass
        POSTGRES_DB          = "mailmandb"
        POSTGRES_INITDB_ARGS = "--locale-provider=icu --icu-locale=en-GB"
      }
      service {
        name = "mailman-postgres"
        port = "postgres"
        check {
          type     = "script"
          command  = "/bin/sh"
          args     = ["-c", "pg_isready --dbname mailmandb -U mailman"]
          interval = "10s"
          timeout  = "5s"
        }
      }
      config {
        image = "postgres:16.3-alpine3.20"
        ports = ["postgres"]
      }
    }

    task "mailman-core" {
      resources {
        cores  = 1
        memory = 4096
      }
      constraint {
        attribute = "${attr.cpu.arch}"
        value     = "amd64"
      }

      service {
        name = "mailman-api"
        port = "mailman_api"
        # check {
        #   type = "http"
        #   path = "/"
        #   interval = "10s"
        #   timeout = "5s"
        # }

      }
      driver = "docker"
      template {
        data        = <<EOF
        DATABASE_URL="postgresql://${var.postgres_user}:${var.postgres_password}@{{ env "NOMAD_ADDR_postgres" }}/mailmandb"
        DATABASE_TYPE="postgres"
        DATABASE_CLASS="mailman.database.postgresql.PostgreSQLDatabase"
        HYPERKITTY_API_KEY="${var.hyperkitty_api_key}"
        HYPERKITTY_URL="http://{{ env "NOMAD_ADDR_mailman-web" }}/hyperkitty"
        ALLOWED_HOSTS={{ env "NOMAD_IP_mailman-http" }}
        EOF
        env         = true
        destination = "local/env"
      }
      config {
        image = "maxking/mailman-core:0.5.2"
        ports = ["mailman_api"]
      }
    }

    task "mailman-web" {
      resources {
        cpu    = 500
        memory = 1024
      }
      constraint {
        attribute = "${attr.cpu.arch}"
        value     = "amd64"
      }
      service {
        name = "mailman-web"
        port = "mailman_http"
        # check {
        #   type = "http"
        #   path = "/"
        #   interval = "10s"
        #   timeout = "5s"
        # }
      }
      driver = "docker"
      template {
        data        = <<EOF
        DATABASE_URL="postgresql://${var.postgres_user}:${var.postgres_password}@{{ env "NOMAD_ADDR_postgres" }}/mailmandb"
        DATABASE_TYPE="postgres"
        SECRET_KEY="${var.secret_key}"
        MAILMAN_HOSTNAME="{{ env "NOMAD_IP_mailman-api" }}"
        HYPERKITTY_API_KEY="${var.hyperkitty_api_key}"
        MAILMAN_ADMIN_USER="admin"
        MAILMAN_ADMIN_EMAIL="admin@boss.com"
        MAILMAN_REST_URL="http://{{ env "NOMAD_ADDR_mailman_api" }}"
        ALLOWED_HOSTS={{ env "NOMAD_IP_mailman-core" }}
        EOF
        env         = true
        destination = "local/env"
      }
      config {
        image    = "maxking/mailman-web:0.5.2"
        ports    = ["mailman_http", "mailman_usgi"]
        hostname = "mailman-web"
      }
    }
  }
}
