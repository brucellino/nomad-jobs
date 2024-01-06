variable "promtail_version" {
  description = "Version of Promtail to deploy"
  type        = string
  default     = "2.9.3"
}

job "promtail" {
  priority = "90"
  meta {
    auto-backup      = true
    backup-schedule  = "@daily"
    backup-target-db = "postgres"
  }
  datacenters = ["dc1"]
  type        = "system"
  update {
    max_parallel      = 2
    health_check      = "checks"
    min_healthy_time  = "10s"
    healthy_deadline  = "5m"
    progress_deadline = "10m"
    auto_revert       = true
    auto_promote      = true
    canary            = 1
    stagger           = "30s"
  }
  group "promtail" {
    count = 1
    update {
      max_parallel = 2
      canary       = 1
      stagger      = "30s"
    }
    network {
      port "http" {}
      port "grpc" {}
    }

    service {
      name = "promtail"
      tags = ["http"]
      port = "http"

      check {
        name     = "promtail-alive"
        type     = "tcp"
        interval = "20s"
        timeout  = "15s"
      }

      check {
        name     = "Promtail HTTP"
        type     = "http"
        path     = "/ready"
        interval = "10s"
        timeout  = "5s"
        port     = "http"

        check_restart {
          limit           = 2
          grace           = "60s"
          ignore_warnings = false
        }
      }
    }

    service {
      name = "promtail-grpc"
      tags = ["grpc"]
      port = "grpc"
    }

    restart {
      attempts = 1
      interval = "10m"
      delay    = "15s"
      mode     = "delay"
    }

    ephemeral_disk {
      size    = 11
      migrate = true
      sticky  = true
    }

    task "promtail" {
      # The "driver" parameter specifies the task driver that should be used to
      # run the task.
      driver = "raw_exec"

      config {
        command = "promtail"
        args    = ["-config.file=local/promtail.yml"]
      }

      artifact {
        source      = "https://github.com/grafana/loki/releases/download/v${var.promtail_version}/promtail-linux-${attr.cpu.arch}.zip"
        destination = "local/promtail"
        mode        = "file"
      }
      logs {
        max_files     = 1
        max_file_size = 10
      }

      resources {
        cpu    = 250 # 500 MHz
        memory = 150 # 256MB
      }


      template {
        data          = file("templates/promtail.yml.tpl")
        destination   = "local/promtail.yml"
        change_mode   = "restart"
        change_signal = "SIGHUP"
      }
    }
  }
}
