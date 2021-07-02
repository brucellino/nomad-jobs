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
        source      = "https://github.com/fabiolb/fabio/releases/download/v1.5.15/fabio-1.5.15-go1.15.5-linux_arm"
        destination = "local/"
      }

      driver = "raw_exec"

      config {
        command = "local/fabio-1.5.15-go1.15.5-linux_arm"
      }

      resources {
        cpu = 100

        memory = 64
      }
    }
  }
}
