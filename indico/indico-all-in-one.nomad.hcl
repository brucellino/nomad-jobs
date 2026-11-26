// Indico job definition modelled as 3-tier workload
// Each tier gets a group
job "indico" {
  vault {}
  secret "github" {
    provider = "vault"
    path     = "hashiatho.me-v2/github"
    config {
      engine = "kv_v2"
    }
  }
  group "frontend" {
    network {
      port "http" {
        to = 80
      }
      port "redis" {
        static = 6379
      }
    }

    reschedule {
      interval       = "30m"
      delay          = "30s"
      delay_function = "constant"
      max_delay      = "120s"
      unlimited      = true
    }

    restart {
      attempts         = 3
      render_templates = true
      delay            = "30s"
      mode             = "fail"
    }

    migrate {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "20s"
      healthy_deadline = "10m"
    }

    update {
      max_parallel      = 1
      health_check      = "checks"
      min_healthy_time  = "20s"
      healthy_deadline  = "10m"
      progress_deadline = "15m"
      auto_revert       = true
      auto_promote      = true
      canary            = 1
      stagger           = "20s"
    }
    count = 1
    // serves user requests, exposed to internet. Low resources
    task "nginx" {
      resources {
        cpu    = 100
        memory = 256
      }
      driver         = "docker"
      shutdown_delay = "30s"
      config {
        image = "nginx:stable-alpine"
        ports = ["http"]
      }
      env {
        NGINX_PORT = "8080"
      }
      service {
        port = "http"

        check {
          interval = "20s"
          type     = "http"
          port     = "http"
          path     = "/"
          timeout  = "5s"
        }
      }
      template {
        data        = file("nginx.conf")
        destination = "local/nginx.conf" # Must be mounted into the container later
      }
    }
    task "redis" {
      resources {
        cpu    = 100
        memory = 256
      }
      driver         = "docker"
      shutdown_delay = "30s"
      config {
        image = "redis:8-alpine"
        ports = ["redis"]
      }
      service {
        port = "redis"

        check {
          interval = "20s"
          type     = "tcp"
          port     = "redis"
          timeout  = "5s"
        }
      }
    }
  }

  #   group "application" {
  #     count = 1
  #
  #     // Runs the actual application. High resources, disposable
  # #     task "indico" {
  # #       resources {
  # #         cpu = 1000
  # #         memory = 1024
  # #       }
  # #       driver = "docker"
  # #       config {
  # #         image = "ghcr.io/hashi-at-home/indico" # We need to build this
  # #         auth {
  # #           username = "brucellino"
  # #           password = "${secret.github.ghcr_token}"
  # #         }
  # #       }
  # #
  # #     }
  #   }

  group "backend" {
    network {
      port "pg18" {
        to = "5432"
      }
      port "celery" {
        to = 5672
      }
    }
    count = 1
    // Handles events and persists data, high reliability and elasticity
    task "celery" {
      vault {}
      driver = "docker"
      # Reuse the same indico image as before, since it has celery
      # configured on it
      config {
        image   = "ghcr.io/hashi-at-home/indico:latest"
        command = "/local/run-celery.sh"
        ports   = ["celery"]
        auth {
          username = "brucellino"
          password = "${secret.github.ghcr_token}"
        }
      }
      template {
        data        = <<EOT
INDICO_CONFIG=local/indico.conf /opt/indico/.venv/bin/indico celery worker -B
      EOT
        destination = "local/run-celery.sh"
        perms       = "0777"
      }
      template {
        data        = <<EOT
{{ with secret "hashiatho.me-v2/indico" }}
# General settings
SQLALCHEMY_DATABASE_URI = 'postgresql://{{ .Data.data.db_user }}:{{ .Data.data.db_pass }}@{{ env "NOMAD_IP_pg18" }}:{{ env "NOMAD_PORT_pg18" }}/indico'
SECRET_KEY = b'Kb\xca\xe1O\xad\x00>\x96\xfctx\x9b^DX\x9f\x08\xfb\x86\xe2\x08ckg\xbb\xea\xd6t\xf1\xbb\x82'
CELERY_BROKER = 'redis://indico-redis-frontend.service.consul:6379/0'
REDIS_CACHE_URL = 'redis://indico-redis-frontend.service.consul:6379/1'
DEFAULT_TIMEZONE = 'Europe/Rome'
DEFAULT_LOCALE = 'en_GB'
ENABLE_ROOMBOOKING = False
CACHE_DIR = '/opt/indico/cache'
TEMP_DIR = '/opt/indico/tmp'
LOG_DIR = '/opt/indico/log'
LOCAL_PASSWORD_MIN_LENGTH = 15
CSP_ENABLED = True
STORAGE_BACKENDS = {'default': 'fs:local/archive'}
ATTACHMENT_STORAGE = 'default'

# Email settings
SMTP_SERVER = ('lol.com', 25)
SMTP_USE_TLS = True
SMTP_LOGIN = '{{ .Data.data.smtp_login }}'
SMTP_PASSWORD = '{{ .Data.data.smtp_password }}'
SUPPORT_EMAIL = 'lol@nope.com'
PUBLIC_SUPPORT_EMAIL = 'lol@nope.com'
NO_REPLY_EMAIL = 'noreply@nope.com'
{{ end }}
        EOT
        destination = "local/indico.conf"
      }
    }
    #

    task "db18" {
      vault {}
      # This one is debatable - deploying the database together with the app
      # May be a recipe for disaster if things die.
      # Better to have an external database in prod
      resources {
        cpu    = 100
        memory = 1024
      }
      driver = "docker"
      config {
        image = "postgres:18-alpine"
        ports = ["pg18"]
      }
      template {
        data        = <<EOT
{{ with secret "hashiatho.me-v2/indico" }}
POSTGRES_PASSWORD={{ .Data.data.db_pass }}
POSTGRES_USER={{ .Data.data.db_user }}
POSTGRES_DB="indico"
{{ end }}
        EOT
        destination = "local/db.env"
        env         = true
      }
    }
  }
}
