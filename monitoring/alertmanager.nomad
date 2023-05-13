job "alertmanager" {
  datacenters = ["dc1"]

  type = "service"

  meta {
    auto-backup      = true
    backup-schedule  = "@daily"
    backup-target-db = "postgres"
  }

  group "alerting" {
    count = 1

    network {
      mode = "host"

      port "alertmanager_ui" {
        static = 9093
        to     = 9093
      }
    }

    restart {
      attempts = 2

      interval = "30m"

      delay = "15s"

      mode = "fail"
    }

    ephemeral_disk {
      size = 300
    }

    task "alertmanager" {
      driver = "raw_exec"

      constraint {
        attribute = attr.cpu.arch
        value     = "arm64"
      }

      artifact {
        source      = "https://github.com/prometheus/alertmanager/releases/download/v0.22.2/alertmanager-0.22.2.linux-armv6.tar.gz"
        destination = "local/"

        options {
          checksum = "sha256:8d31f59b52f69a77f869bd124e87a5fc9434a9f4fce5325a980d35acd269f71c"
        }
      }

      config {
        command = "local/alertmanager-0.22.2.linux-armv6/alertmanager"
        args    = ["--config.file=local/alertmanager-0.22.2.linux-armv6/alertmanager.yml"]
      }

      resources {
        cpu    = 125
        memory = 256
      }

      service {
        name = "alertmanager"
        tags = ["urlprefix-/alertmanager strip=/alertmanager"]
        port = "alertmanager_ui"

        check {
          name     = "alertmanager_ui port alive"
          type     = "http"
          path     = "/-/healthy"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
