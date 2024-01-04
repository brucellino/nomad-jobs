variable "node_exporter_version" {
  description = "Version of node exporter"
  type        = string
  default     = "1.5.0"
}

job "node-exporter" {
  priority = 100
  meta {
    auto-backup      = true
    backup-schedule  = "@daily"
    backup-target-db = "postgres"
  }
  datacenters = ["dc1"]
  type        = "system"

  group "node-exporter" {
    count = 1
    network {
      port "http" {}
    }

    service {
      name = "node-exporter"
      tags = ["http"]
      port = "http"

      check {
        name     = "node-exporter-alive"
        type     = "tcp"
        interval = "20s"
        timeout  = "15s"
      }

      check {
        name     = "Node-exporter healthy"
        type     = "http"
        path     = "/metrics"
        interval = "10s"
        timeout  = "5s"
      }
    }

    ephemeral_disk {
      size = 300
    }

    task "node-exporter" {
      # The "driver" parameter specifies the task driver that should be used to
      # run the task.
      driver = "raw_exec"

      config {
        command = "node_exporter/node_exporter-${var.node_exporter_version}.linux-arm64/node_exporter"
        args = [
          "--web.listen-address=:${NOMAD_PORT_http}"
        ]
      }

      artifact {
        source      = "https://github.com/prometheus/node_exporter/releases/download/v${var.node_exporter_version}/node_exporter-${var.node_exporter_version}.linux-arm64.tar.gz"
        destination = "local/node_exporter"
        mode        = "any"
      }

      resources {
        cpu    = 60
        memory = 125
      }
    }
  }
}
