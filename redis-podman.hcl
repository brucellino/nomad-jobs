variable "redis_version" {
  type = string
  default = "6.0"
  description = "version of redis to run"
}
job "redis" {
  datacenters = ["dc1"]
  type        = "service"
  migrate {
    max_parallel     = 1
    health_check     = "checks"
    min_healthy_time = "10s"
    healthy_deadline = "5m"
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
        image = "docker://redis:${var.redis_version}"
        ports = ["redis"]
      }
    }
  }
}
