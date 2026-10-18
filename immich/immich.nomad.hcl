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
      attempts         = 2
      delay            = "5m"
      interval         = "10m"
      render_templates = true
      mode             = "delay"
    }

    update {

    }
    task "redis" {
      shutdown_delay = "5s"
      resources {
        cpu    = 128 # MHz
        memory = 128 # MB
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
