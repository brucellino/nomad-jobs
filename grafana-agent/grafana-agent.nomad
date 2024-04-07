variable "graf_agent_rel_url" {
  description = "Base URL for grafana release packages."
  default     = "https://github.com/grafana/agent/releases/download"
}
variable "graf_agent_version" {
  description = "Grafana Agent version to be used."
  default     = "0.40.3"
}
job "grafana-agent" {
  group "nodes" {
    task "agent" {
      driver = "raw_exec"
      template {
        source      = file("grafana-agent.yml.tmpl")
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
