job "redis" {
  datacenters = ["dc1"]
  type        = "service"

  group "cache" {
    network {
      port "redis" { to = 6379 }
    }
    service {
        tags = ["cache","redis","urlprefix-/redis"]
        port = "redis"
        check {
          name = "redis_probe"
          type = "tcp"
          interval = "10s"
          timeout = "1s"
        }
      }
    task "redis" {
      driver = "podman"
      config {
        image = "docker://redis"
        ports = ["redis"]
      }
    }
  }
}
