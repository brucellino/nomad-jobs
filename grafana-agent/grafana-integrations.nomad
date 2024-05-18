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

job "grafana-monitoring" {
  vault {}
  type = "service"
  group "consul" {
    restart {
      render_templates = true
      attempts         = 2
      interval         = "5m"
      mode             = "delay"
    }
    update {
      max_parallel      = 3
      health_check      = "checks"
      min_healthy_time  = "10s"
      healthy_deadline  = "5m"
      progress_deadline = "10m"
      auto_revert       = true
      auto_promote      = true
      canary            = 1
    }
    network {
      port "http" {}
      port "grpc" {}
    }

    task "agent" {
      resources {
        memory = 512
        cpu    = 500
      }
      identity {
        name        = "vault"
        aud         = ["vault.io"]
        env         = true
        file        = true
        change_mode = "restart"
        ttl         = "1h"
      }

      service {
        port = "http"
        name = "grafana-agent-consul-http"
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
        name = "grafana-agent-consul-grpc"
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
        data        = file("grafana-integrations-consul.yml.tmpl")
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
          "-server.grpc.address", "${NOMAD_ADDR_grpc}",
          "-disable-reporting"
        ]
      }
    }
  }
}
