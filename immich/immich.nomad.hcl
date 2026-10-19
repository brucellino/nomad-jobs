job "immich" {
  ui {
    description = "Immich is a photo sharing app."
    link {
      label = "Documentation"
      url   = "https://docs.immich.app/"
    }
    link {
      label = "Website"
      url   = "https://immich.app/"
    }
  }
  reschedule {
    # always reschedule the job
    interval       = "20m"
    delay          = "30s"
    delay_function = "exponential"
    max_delay      = "120s"
    unlimited      = true
  }

  update {
    max_parallel      = 2
    health_check      = "checks"
    min_healthy_time  = "10s"
    healthy_deadline  = "5m"
    progress_deadline = "10m"
    auto_revert       = true
    auto_promote      = true
    canary            = 1
    stagger           = "30s"
  }

  group "backing" {
    vault {}
    # Constraints
    # Affinity
    affinity {
      # Prefer nodes with little ram
      attribute = "${attr.memory.totalbytes}"
      value     = "1000000000" # 1GB
      operator  = "<"
      weight    = 90
    }

    # Spread

    count = 1

    consul {}

    ephemeral_disk {
      migrate = true
      size    = 2048
      sticky  = true
    }
    # meta
    meta {
      docs-url = "https://immich.app"
      owner    = "brucellino"
    }
    # migrate
    migrate {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "15s"
      healthy_deadline = "15m"
    }

    network {
      port "redis" {
        to = 6379
      }
      port "db" {
        to = 5432
      }
    }

    restart {
      attempts         = 2
      delay            = "5m"
      interval         = "10m"
      render_templates = true
      mode             = "delay"
    }

    update {
      max_parallel      = 2
      health_check      = "checks"
      min_healthy_time  = "10s"
      healthy_deadline  = "5m"
      progress_deadline = "10m"
      auto_revert       = true
      auto_promote      = true
      canary            = 1
      stagger           = "30s"
    }

    volume "db" {
      type            = "host"
      source          = "immich-db"
      attachment_mode = "file-system"
      access_mode     = "single-node-writer"

    }
    task "redis" {
      shutdown_delay = "5s"
      resources {
        cpu    = 128 # MHz
        memory = 128 # MB
      }
      // script check redis-cli ping | grep -q PONG || exit 1
      driver = "docker"
      config {
        image = "docker.io/valkey/valkey:9"
        ports = ["redis"]
      }
      service {
        port = "redis"
        check {
          type     = "script"
          command  = "redis-cli"
          args     = ["ping"]
          interval = "15s"
          timeout  = "3s"
        }
      }
    }
    task "postgres" {
      driver         = "docker"
      shutdown_delay = "5s"
      resources {
        cpu    = 1024
        memory = 1204
      }
      config {
        image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0"
        ports = ["db"]
      }
      service {
        port = "db"
        check {
          name     = "postgres-server"
          type     = "tcp"
          interval = "15s"
          timeout  = "3s"
        }

        check {
          name      = "Postgres Server Check"
          type      = "script"
          command   = "/usr/bin/pg_isready"
          args      = ["-U", "${POSTGRES_USER}", "-d", "${POSTGRES_DB}"]
          interval  = "5s"
          timeout   = "2s"
          on_update = "ignore_warnings"
        }
      }
      volume_mount {
        volume      = "db"
        destination = "/var/lib/postgresql"
      }
      template {
        data        = <<EOT
{{ with secret "platform-workloads/data/immich" }}
POSTGRES_PASSWORD = "{{ .Data.data.postgres_password }}"
POSTGRES_USER = "{{ .Data.data.postgres_user }}"
POSTGRES_DB = "{{ .Data.data.postgres_db }}"
{{ end }}
POSTGRES_INITDB_ARGS = "--data-checksums"
EOT
        env         = true
        destination = "secrets/db.env"
      } // db env
    }   // db backing task
  }     // db backing group

  group "front" {
    vault {}
    # Constraints
    # Affinity
    affinity {
      # Prefer nodes with large ram
      attribute = "${attr.memory.totalbytes}"
      value     = "3000000000" # 3GB
      operator  = ">"
      weight    = 90
    }

    # Spread

    count = 1

    consul {}

    ephemeral_disk {
      migrate = true
      size    = 2048
      sticky  = true
    }
    # meta
    meta {
      docs-url = "https://immich.app"
      owner    = "brucellino"
    }
    # migrate
    migrate {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "15s"
      healthy_deadline = "15m"
    }

    network {
      port "immich-server" {
        to = 2283
      }
    }

    restart {
      attempts         = 2
      delay            = "5m"
      interval         = "10m"
      render_templates = true
      mode             = "delay"
    }

    update {
      max_parallel      = 2
      health_check      = "checks"
      min_healthy_time  = "10s"
      healthy_deadline  = "5m"
      progress_deadline = "10m"
      auto_revert       = true
      auto_promote      = true
      canary            = 1
      stagger           = "30s"
    }

    task "server" {
      resources {
        cores  = 3
        memory = 6144
      }
      driver = "docker"
      config {
        image = "ghcr.io/immich-app/immich-server:commit-1ffad72882d82221b06f4c5152d9c3eb15fb8016"
        # init = true
        # init_path = "/usr/bin/tini"
        entrypoint = ["tini", "--", "/bin/bash", "-c"]
        command    = "start.sh"
        ports      = ["immich-server"]
        #  logging = {
        #   driver = "nomad"
        # }

      }
      template {
        change_mode = "restart"
        data        = <<EOT
{{ with secret "platform-workloads/data/immich" }}
DB_USERNAME="{{ .Data.data.postgres_user }}"
DB_PASSWORD="{{ .Data.data.postgres_password }}"
DB_DATABASE_NAME="{{ .Data.data.postgres_db }}"
DB_STORAGE_TYPE="HDD"
{{ end }}
        EOT
        destination = "secrets/immich.env"
        env         = true
      }
      template {
        change_mode = "restart"
        data        = <<EOT
{{ range service "immich-backing-postgres" }}
DB_HOSTNAME="{{ .Address }}"
DB_PORT={{ .Port }}
{{ end }}
{{ range service "immich-backing-redis" }}
REDIS_HOSTNAME="{{ .Address }}"
REDIS_PORT={{ .Port }}
{{ end }}
        EOT
        destination = "local/immich.env"
        env         = true
      } // env template
    }
  } // front group
}
