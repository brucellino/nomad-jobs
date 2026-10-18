job "immich" {

  reschedule {
    # always reschedule the job
    interval       = "20m"
    delay          = "30s"
    delay_function = "exponential"
    max_delay      = "120s"
    unlimited      = true
  }

  restart {
    attempts         = 2
    delay            = "5m"
    interval         = "10m"
    render_templates = true
    mode             = "delay"
  }
  group "backing" {

    # Constraints
    # Affinity

    affinity {
      # Prefer nodes with little ram
      attribute = "${attr.memory.totalbytes}"
      value     = "1000000000" # 1GB
      operator  = "<"
      weight    = 90
    }

    # spread

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
      max_parallel = 1
      # health_check = "checks"
      # min_healthy_time = "15s"
      # healthy_deadline = "15m"
    }

    network {
      port "redis" {
        to = 6379
      }
    }



    restart {

    }

    update {

    }
    task "redis" {
      shutdown_delay = "5s"
      resources {
        cpu    = 128
        memory = 128
      }
      // script check redis-cli ping | grep -q PONG || exit 1
      driver = "podman"
      config {
        image = "docker.io/valkey/valkey:9"
        ports = ["redis"]
      }
    }
    # task "postgres" {
    #   driver "podman"
    #   config {
    #     image = "docker.io/postgres:18-alpine"
    #   }
    # }
  }
}
