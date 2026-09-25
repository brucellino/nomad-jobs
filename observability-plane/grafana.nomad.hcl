# Standalone Observability stack
# Group should contain backing database
# with Grafana starting after database has been started

# Expects persistent volume for SQL data

variable "grafana_version" {
  type        = string
  default     = "13.2"
  description = "Grafana version"
}

job "grafana" {

  vault {}

  datacenters = ["dc1"]
  type        = "service"

  update {
    max_parallel      = 1
    min_healthy_time  = "5s"
    healthy_deadline  = "15m"
    progress_deadline = "30m"
    auto_revert       = true
    auto_promote      = true
    canary            = 1
  }

  migrate {
    max_parallel     = 1
    health_check     = "checks"
    min_healthy_time = "5s"
    healthy_deadline = "30m"
  }

  group "back" {
    network {
      port "postgres" {
        to = 5432
      }
      port "grafana_srv" {
        to = 3000
      }
    }

    volume "pg_db" {
      type            = "host"
      source          = "grafana-pg-db"
      read_only       = false
      sticky          = true
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    task "postgres" {
      leader = true
      driver = "docker"
      config {
        image = "postgres:18-alpine"
        ports = ["postgres"]
      }

      volume_mount {
        volume      = "pg_db"
        destination = "/var/lib/postgresql"
      }
      template {
        data        = <<EOT
{{ with secret "hashiatho.me-v2/observability "}}
POSTGRES_USER="{{ .Data.data.postgres_root_user }}"
POSTGRES_PASSWORD="{{ .Data.data.postgres_root_password }}"
POSTGRES_DB=grafana
{{ end }}
        EOT
        destination = "secrets/db.env"
        env         = true
      }
      shutdown_delay = "30s"
      service {
        provider = "consul"
        identity {
          aud = ["consul.io"]
          ttl = "24h"
        }
        tags      = ["db", "dashboard", "urlprefix-/postgres:5432 proto=tcp"]
        port      = "postgres"
        on_update = "require_healthy"

        check {
          type     = "tcp"
          port     = "postgres"
          name     = "pg_alive"
          interval = "30s"
          timeout  = "5s"
        }
      }
      resources {
        cpu    = 512
        memory = 1024
      }
    }
  }

  group "front" {
    network {
      port "grafana_srv" {
        to = 3000
      }
    }
    task "wait-for-db" {
      lifecycle {
        hook = "prestart"
      }
      driver = "raw_exec"
      config {
        command = "bash"
        args    = ["local/wait_for_it.sh"]
      }
      template {
        change_mode = "restart"
        wait {
          min = "15s"
          max = "60s"
        }
        data        = <<EOT
#!/bin/env bash
{{ range service "grafana-back-postgres" }}
while ! nc -z {{ .Address }} {{ .Port }} ; do sleep 1 ; done
{{ end }}
        EOT
        destination = "local/wait_for_it.sh"
      }
    }

    task "grafana" {
      shutdown_delay = "60s"
      service {
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.grafana.entrypoints=http",
          "traefik.http.middlewares.grafana-stripprefix.stripprefix.prefixes=grafana",
          "traefik.http.routers.grafana.rule=PathPrefix(`/grafana`)",
          "traefik.http.routers.grafana.middlewares=grafana-stripprefix",
          "traefik.http.routers.grafana.observability.metrics=true",
          "traefik.http.routers.grafana.service=grafana-front-grafana"
        ]
        port = "grafana_srv"

        check {
          port     = "grafana_srv"
          name     = "grafana-api"
          path     = "/api/health"
          type     = "http"
          interval = "5s"
          timeout  = "1s"
        }
      }
      driver = "docker"
      logs {
        max_files     = 2
        max_file_size = 15
      }
      resources {
        cpu    = 2000
        memory = 2048
      }

      config {
        image = "grafana/grafana:${var.grafana_version}"
        args = [
          # "-homepath=${NOMAD_ALLOC_DIR}/grafana-${var.grafana_version}",
          "--config=${NOMAD_ALLOC_DIR}/conf.ini"
        ]
        ports = ["grafana_srv"]
      }

      template {
        data        = file("templates/grafana.ini.tpl")
        destination = "${NOMAD_ALLOC_DIR}/conf.ini"
      } // Configuration template
    }   // Grafana server task
  }     // front server group
}
