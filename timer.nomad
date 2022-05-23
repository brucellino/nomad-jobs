job "timer" {
  region = "global"
  datacenters = ["dc1"]
  type = "batch"
  meta {
    auto-backup = true
    backup-schedule = "@daily"
    backup-target-db = "postgres"
  }
  group "script" {
    volume "job_inbound" {
      type = "host"
      source = "job_inbound"
      read_only = false
    }
    count = 1
    task "script" {
      volume_mount {
        volume = "job_inbound"
        destination = "/scratch"
      }
      artifact {
        source = "/timer.py"
        destination = "local/timer.py"
        mode = "file"
      }
      // constraint {
      //   attribute = "${meta.cached_binaries}"
      //   operator = "set_contains"
      //   value = "python3"
      // }

      constraint {
        attribute = "${attr.unique.hostname}"
        value= "sense.station"
      }

      driver = "exec"
      user = "becker"
      config {
        command = "python3"
        args = ["local/timer.py"]
      }
      resources {
        cpu = 125
        memory = 100
      }
    }
  }
}
