variable "graf_agent_rel_url" {
  description = "Base URL for grafana release packages."
  type        = string
  default     = "https://github.com/grafana/agent/releases/download"
}
variable "graf_agent_version" {
  description = "Grafana Agent version to be used."
  type        = string
  default     = "0.40.3"
}

variable "scrape_interval" {
  description = "Default scrape interval"
  type        = string
  default     = "60s"
}

job "grafana-agent" {
  vault {}
  type = "system"
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
        name = "grafana-agent-http"
        check {
          type     = "http"
          name     = "agent_health"
          path     = "/-/healthy"
          interval = "20s"
          timeout  = "5s"
        }
      }

      service {
        port = "grpc"
        name = "grafana-agent-grpc"
        check {
          type     = "tcp"
          interval = "20s"
          timeout  = "5s"
        }
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
        args = [
          "-config.file", "local/agent.yml",
          "-server.http.address", "${NOMAD_ADDR_http}",
        "-server.grpc.address", "${NOMAD_ADDR_grpc}"]
      }
    }
  }
}
