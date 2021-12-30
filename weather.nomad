job "weather" {
  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "inky.station"
  }

  meta {
    team = "inky"
    sdk  = "python3"
    ever = "5min"
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
    }
  }
}
