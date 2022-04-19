job "weather" {
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
