job "upgrade" {
  type = "sysbatch"
  datacenters = ["dc1"]
  periodic {
    cron = "@weekly"
    time_zone = "Europe/Rome"
  }
  group "upgrade" {
    # a raw exec job to update the apt cache and apply all upgrades
    task "upgrade" {
      driver = "raw_exec"
      resources {
        cpu = 100
        memory = 128
      }
      config {
        command = "/bin/bash"
        args = ["-c", "sudo apt-get update && sudo apt-get upgrade -y"]
      }
    }
  }
}
