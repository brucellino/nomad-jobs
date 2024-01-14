variable "memcached_version" {
  type    = string
  default = "1.6.23-alpine"
}

job "memcached" {
  datacenters = ["dc1"]
  type        = "service"
  name        = "memcached"
  priority    = 100

  update {
    max_parallel      = 1
    health_check      = "checks"
    min_healthy_time  = "5s"
    healthy_deadline  = "300s"
    progress_deadline = "10m"
    auto_revert       = true
    auto_promote      = true
    canary            = 1
  }

  migrate {
    max_parallel     = 2
    health_check     = "checks"
    min_healthy_time = "10s"
    healthy_deadline = "5m"
  }

  group "server" {
    count = 1

    network {
      port "memcached" {
        to = 11211
      }
    }
    service {
      name      = "memcached-server"
      port      = "memcached"
      on_update = "require_healthy"

      check {
        name     = "memcached_ready"
        type     = "tcp"
        port     = "memcached"
        interval = "10s"
        timeout  = "3s"
      }
    }

    task "server" {
      driver = "docker"
      config {
        image = "docker.io/memcached:${var.memcached_version}"
        ports = ["memcached"]
      }

      resources {
        cpu    = 1000
        memory = 200
      }
    }
  }
}
