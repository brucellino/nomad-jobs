job "fabio" {
  datacenters = ["dc1"]
  type = "system"
  meta {
    auto-backup = true
    backup-schedule = "@daily"
    backup-target-db = "postgres"
  }
  group "fabio" {
    network {
      port "lb" {
        static = 9999
      }

      port "ui" {
        static = 9998
      }
    }
    restart {
      attempts = 3
      interval = "10m"
      delay = "15s"
      mode = "delay"
    }

    task "fabio" {
      artifact {
        source      = "https://github.com/fabiolb/fabio/releases/download/v1.6.0/fabio-1.6.0-linux_${attr.cpu.arch}"
        destination = "local/fabio"
        mode = "file"
      }

      driver = "exec"

      config {
        command = "local/fabio"
      }

      resources {
        cpu = 100
        memory = 64
      }
    }
  }
}
