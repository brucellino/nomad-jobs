variable "graf_agent_rel_url" {
  description = "Base URL for grafana release packages."
  default     = "https://github.com/grafana/agent/releases/download"
}
variable "graf_agent_version" {
  description = "Grafana Agent version to be used."
  default     = "0.40.3"
}

variable "gcloud_metrics_id" {
  description = "Grafana Cloud metrics Id"
  default     = 988263
}

variable "gcloud_logs_id" {
  description = "Grafana Cloud Loki Id"
  default     = 596739
}

variable "scrape_interval" {
  description = "Default scrape interval"
  default     = "60s"
}

job "grafana-agent" {
  vault {}
  group "nodes" {
    network {
      port "http" {}
      port "grpc" {}
    }
    task "agent" {
      identity {
        name        = "vault"
        aud         = ["vault.io"]
        env         = true
        file        = true
        change_mode = "restart"
      }

      service {
        port = "http"
        name = "grafana-agent-${attr.unique.hostname}-http"
      }
      env {
        HOSTNAME = attr.unique.hostname
      }
      driver = "raw_exec"
      template {
        data        = file("grafana-agent.yml.tmpl")
        destination = "local/agent.yml"
      }
      artifact {
        source      = "${var.graf_agent_rel_url}/v${var.graf_agent_version}/grafana-agent-linux-${attr.cpu.arch}.zip"
        destination = "local/grafana-agent"
        mode        = "file"
      }
      config {
        command = "local/grafana-agent"
        args    = ["-config.file", "local/agent.yml"]
      }
      service {

      }
    }
  }
}
