job "weather" {

   affinity {
    attribute = "${attr.unique.hostname}"
    value     = "inky"
    weight    = 100
  }
  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "inky"
  }

  meta {
    team = "inky"
    sdk  = "python3"
    every = "5min"
  }

  periodic {
    cron             = "@hourly"
    prohibit_overlap = true
    time_zone        = "Europe/Rome"
  }

  type        = "batch"
  datacenters = ["dc1"]

  group "weather" {
    ephemeral_disk {
        migrate = true
        size    = 100
        sticky  = true
      }
    task "weather" {
      driver = "raw_exec"

      config {
        command = "python3"
        args    = ["/home/becker/inky/examples/phat/weather-phat.py"]
      }

      resources {
        cpu    = 256
        memory = 128
      }

      logs {
        max_files     = 5
        max_file_size = 5
      }
      service {
        tags = ["weather"]
        // port = "weather"
        meta {
          team = "inky"
          sdk  = "python3"
          every = "5min"
        }
        check {
          type = "script"
          name = "check_python"
          command = "python3"
          args = ["--version" ]
          interval = "20s"
          timeout = "5s"

          check_restart {
            limit = 3
            grace = "90s"
            ignore_warnings = false
          }
        }
      }
    }
  }
}
