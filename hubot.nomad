job "hubot" {
  datacenters = ["dc1"]
  type        = "service"

  update {
    max_parallel      = 1
    min_healthy_time  = "10s"
    healthy_deadline  = "3m"
    progress_deadline = "10m"
    auto_revert       = false
    canary            = 1
  }

  migrate {
    max_parallel     = 2
    health_check     = "checks"
    min_healthy_time = "10s"
    healthy_deadline = "1m"
  }

  group "hubot" {
    count = 1

    network {
      port "db" {
        to = 6379
      }

      port "express" {
        to = 8080
      }
    } // network

    service {
      name = "hubot"
      tags = ["global", "bot"]
      port = "express"

      check {
        name     = "alive"
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
      }
    } // hubot service

    restart {
      # The number of attempts to run the job within the specified interval.
      attempts = 1
      interval = "5m"
      delay    = "15s"
      mode     = "fail"
    }

    ephemeral_disk {
      size = 300
    }

    task "install" {
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }
    }

    task "hubot" {
      driver = "exec"

      config {
        command = "/bin/bash"
        args    = ["-c", "'sleep infinity'"]
      }

      constraint {
        attribute = "${attr.os.name}"
        value     = "ubuntu"
      }
    }
  } // Hubot Group
}
