job "immich" {
  group "backing" {

    # Constraints
    # Affinity
    # Prefer nodes with little ram
    affinity {
      attribute = "${attr.memory.totalbytes}"
      value     = "1000000000" # 1GB
      operator  = "<"
      weight    = 90
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
