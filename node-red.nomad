job "nodered" {
  datacenters = ["dc1"]

  group "automation" {
    count = 1

    network {
      port "ui" {
        static = 1880
      }
    }

    service {
      tags = ["automation", "nodered"]
      port = "ui"

      check {
        type     = "http"
        port     = "ui"
        path     = "/"
        interval = "10s"
        timeout  = "5s"
      }

      check_restart {
        grace = "600s"
        limit = 2
      }
    }

    task "nodered_server" {
      driver = "raw_exec"

      resources {
        cores  = 2
        memory = 800
      }

      config {
        command = "node-red"
      }
    }
  }
}
