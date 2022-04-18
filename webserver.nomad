job "webserver" {
  datacenters = ["dc1"]

  group "webserver" {
    task "server" {
      driver = "docker"

      config {
        image = "hashicorp/demo-prometheus-instrumentation:latest"
      }

      resources {
        cpu    = 500
        memory = 256

        network {
          port "http" {}
        }
      }

      service {
        name = "webserver"
        port = "http"

        tags = [
          "testweb",
          "urlprefix-/webserver strip=/webserver",
        ]

        check {
          type     = "http"
          path     = "/"
          interval = "2s"
          timeout  = "2s"
        }
      }
    }
  }
}
