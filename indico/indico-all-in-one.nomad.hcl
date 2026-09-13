// Indico job definition modelled as 3-tier workload
// Each tier gets a group
job "indico" {
  group "frontend" {
    network {
      port "http" {
        to = 80
      }
      port "redis" {
        to = 6379
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

  # group "application" {
  #   count = 1
  #   // Runs the actual application. High resources, disposable
  #   task "indico" {
  #     driver = "docker"
  #     image = "ghcr.io/hashi-at-home/indico" # We need to build this
  #   }
  # }

  group "backend" {
    count = 1
    // Handles events and persists data, high reliability and elasticity
    # task "celery" {
    #   count = 1 // let's scale this guy eventually
    #   driver = "docker"
    #   # Reuse the same indico image as before, since it has celery
    #   # configured on it
    #   image = "ghcr.io/hashi-at-home/indico"
    # }

    task "db" {
      # This one is debatable - deploying the database together with the app
      # May be a recipe for disaster if things die.
      # Better to have an external database in prod
      driver = "docker"
      config {
        image = "postgres:18-alpine"
      }
      env {
        POSTGRES_PASSWORD = "postgres" # pragma: allowlist secret
        POSTGRES_USER     = "postgres"
        POSTGRES_DB       = "indico"
      }
    }
  }
}
