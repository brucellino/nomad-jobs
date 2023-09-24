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
    crons             = ["*/15 * * * * *"]
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
      user = "root"
      config {
        command = "/usr/bin/python3"
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
    }
  }
}
