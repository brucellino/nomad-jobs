variable "db" {
  type = object({
    image   = string
    version = string
    port    = number
    db_name = string
  })
  default = {
    image   = "bitnami/postgresql"
    version = "16.6.0"
    port    = 5432
    db_name = "reportportal"
  }
  description = "Database configuration"
}

variable "rabbitmq" {
  type = object({
    image   = string
    version = string
    port    = number
  })
  default = {
    image      = "bitnami/rabbitmq"
    version    = "3.13.7-debian-12-r5"
    port       = 5672
    queue_name = "reportportal"
  }
  description = "RabbitMQ configuration"
}

variable "opensearch" {
  type = object({
    image   = string
    version = string
    port    = number
  })
  default = {
    image   = "opensearchproject/opensearch"
    version = "3"
    port    = 9200
  }
  description = "OpenSearch configuration"
}

job "report-portal-backing" {
  reschedule {
    delay          = "30s"
    delay_function = "exponential"
    max_delay      = "1h"
    unlimited      = true
  }

  group "rp" {
    network {
      port "db" {
        to = var.db.port
      }
      port "opensearch" {
        to = var.opensearch.port
      }
      port "rabbit" {
        to = 5672
      }
      port "management" {
        to = 15672
      }
      port "lb" {
        to = 8080
      }
      port "traefik-management" {
        to = 8081
      }
    }
    vault {
      policies    = ["nomad-read", "nomad-workloads", "default"]
      change_mode = "noop"
      env         = true
    }

    restart {
      attempts         = 3
      delay            = "30s"
      render_templates = true
      mode             = "delay"
    }
    // Tasks which require peristent storage and provide backend functionality
    // These include the DB and the API
    task "db" {
      env {
        POSTGRES_DB = var.db.db_name
      }
      vault {
        policies      = ["nomad-read"]
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }
      template {
        data        = <<EOF
{{ with secret "hashiatho.me-v2/data/report_portal" }}
POSTGRES_USER="{{ .Data.data.postgres_user }}"
POSTGRES_PASSWORD="{{ .Data.data.postgres_pass }}"
{{ end }}
        EOF
        destination = "${NOMAD_SECRETS_DIR}/db.env"
        env         = true
      }
      driver = "docker"
      config {
        image = "${var.db.image}:${var.db.version}"
        ports = ["db"]
      }
      resources {
        cpu    = 500
        memory = 1024
      }
      service {
        provider = "consul"
        port     = "db"
        tags     = ["db"]
        check {
          type     = "script"
          command  = "pg_isready"
          args     = ["-d", "$POSTGRES_DB", "-U", "$POSTGRES_USER"]
          interval = "20s"
          timeout  = "5s"
        }
      }
    }

    task "migrations" {
      driver = "docker"
      vault {
        policies      = ["nomad-read"]
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }
      resources {
        cpu    = 256
        memory = 128
      }
      template {
        data        = <<EOF
{{ with secret "hashiatho.me-v2/data/report_portal" }}
POSTGRES_USER="{{ .Data.data.postgres_user }}"
POSTGRES_PASSWORD="{{ .Data.data.postgres_pass }}"
{{ end }}
POSTGRES_SERVER="{{ env "NOMAD_IP_db" }}"
POSTGRES_PORT="{{ env "NOMAD_HOST_PORT_db" }}"
POSTGRES_DB="${var.db.db_name}"
        EOF
        destination = "${NOMAD_SECRETS_DIR}/task.env"
        env         = true
      }
      config {
        image = "reportportal/migrations:5.14.0"
      }
      lifecycle {
        hook = "poststart"
      }
    }

    task "opensearch" {
      service {
        name     = "rp-opensearch"
        port     = "opensearch"
        provider = "consul"
        check {
          name     = "opensearch"
          type     = "http"
          path     = "/_cat/health"
          interval = "10s"
          timeout  = "2s"
        }
      }
      env = {
        "discovery.type"              = "single-node"
        "plugins.security.disabled"   = true
        "bootstrap.memory_lock"       = true
        "OPENSEARCH_JAVA_OPTS"        = "-Xms512m -Xmx512m"
        "DISABLE_INSTALL_DEMO_CONFIG" = true
      }
      driver = "docker"
      config {
        image = "${var.opensearch.image}:${var.opensearch.version}"
        ulimit {
          memlock = "-1:-1"
        }
        ports = ["opensearch"]
      }
      resources {
        cores  = 1
        memory = 2048
      }

      // for rpi5
      constraint {
        attribute = "${attr.unique.hostname}"
        operator  = "set_contains_any"
        value     = "ticklish,monolith"
      }
    }

    task "traefik" {
      driver = "docker"
      config {
        image = "traefik:v2.11.24"
        args = [
          "--providers.consul=true",
          "--providers.consul.endpoints=127.0.0.1:8500",
          "--entrypoints.web.address=:8080", "--entrypoints.traefik.address=:8081",
          "--api.dashboard=true",
          "--api.insecure=true"
        ]
        ports = ["traefik-management", "lb"]
      }
      service {
        provider = "consul"
        name     = "rp-traefik-mgmt"
        port     = "traefik-management"
        tags     = ["traefik-public"]
      }
      service {
        provider = "consul"
        name     = "rp-traefik"
        port     = "lb"
        tags     = ["traefik-public"]
      }
    }

    task "rabbit" {
      vault {
        policies      = ["nomad-read"]
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }
      template {
        data        = <<EOF
{{ with secret "hashiatho.me-v2/data/report_portal" }}
RABBITMQ_DEFAULT_USER="{{ .Data.data.rabbit_user }}"
RABBITMQ_DEFAULT_PASS="{{ .Data.data.rabbit_pass }}"
RABBITMQ_USER="{{ .Data.data.rabbit_user }}"
RABBITMQ_PASSWORD="{{ .Data.data.rabbit_pass }}"
RABBITMQ_ENABLE_LDAP="false"
RABBITMQ_MANAGEMENT_ALLOW_WEB_ACCESS="true"
RABBITMQ_DISK_FREE_ABSOLUTE_LIMIT="50MB"
RABBITMQ_PLUGINS="rabbitmq_consistent_hash_exchange rabbitmq_management rabbitmq_auth_backend_ldap rabbitmq_shovel rabbitmq_shovel_management"
{{ end }}
RABBITMQ_VHOSTS="analyzer"
        EOF
        destination = "${NOMAD_SECRETS_DIR}/rabbitmq.env"
        env         = true
      }
      driver = "docker"
      config {
        image = "${var.rabbitmq.image}:${var.rabbitmq.version}"
        ports = ["rabbit", "management"]
      }
      resources {
        cpu    = 256
        memory = 1024
      }
      service {
        name     = "rp-rabbit"
        port     = "rabbit"
        provider = "consul"
        check {
          type     = "script"
          command  = "rabbitmqctl"
          args     = ["status"]
          interval = "30s"
          timeout  = "5s"
        }
      }

      service {
        name     = "rp-rabbit-management"
        port     = "management"
        provider = "consul"
        check {
          type     = "http"
          path     = "/api"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }
  } // group
}
