job "immich" {
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

    network {
      port "redis" {
        to = 6379
      }
    }
    task "redis" {
      resources {
        cpu    = 128
        memory = 128
      }
      // script check redis-cli ping | grep -q PONG || exit 1
      driver = "podman"
      config {
        image = "docker.io/valkey/valkey:9"
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
