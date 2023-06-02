job "rabbit" {
  datacenters = ["dc1"]
  type = "service"

  update {
    max_parallel = 2
    health_check = "checks"
    auto_revert = true
    auto_promote = true
    canary = 1
  }

  group "main" {
    network {
      mode = "bridge"
      port "ampq" {
        to = 5672
      }
      port "management" {
        to = 15672
      }
      port "monitoring" {
        to = 15692
      }
    }
    task "management" {
      driver = "docker"
      config {
        image = "rabbitmq:3.11-management"
      }

      service {
        name = "rabbitmq-mon"
        tags = ["urlprefix-/rabbit"]
        port = "monitoring"
        check {
          type = "http"
          name = "readiness"
          path = "/metrics"
          interval = "20s"
          timeout = "5s"
        }
      }

      service {
        name = "rabbitmq-ampq"
        tags = ["urlprefix-/ampq"]
        port = "ampq"
        check {
          type = "tcp"
          interval = "30s"
          timeout = "5s"
        }
      }

      service {
        name = "rabbitmq-admin"
        tags = ["urlprefix-/ampq"]
        port = "management"
        check {
          type = "http"
          name = "admin_panel"
          path = "/"
          interval = "30s"
          timeout = "5s"
        }
      }
    }
  }
}
