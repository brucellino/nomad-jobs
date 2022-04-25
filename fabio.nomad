job "fabio" {
  datacenters = ["dc1"]
  type = "system"

  group "fabio" {
    network {
      port "lb" {
        static = 9999
      }

      port "ui" {
        static = 9998
      }
    }

    task "fabio" {
      artifact {
        source      = "https://github.com/fabiolb/fabio/releases/download/v1.6.0/fabio-1.6.0-linux_${attr.cpu.arch}"
        destination = "local/fabio"
        mode = "file"
      }

      driver = "raw_exec"

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
