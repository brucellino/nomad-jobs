job "node-exporter" {
  type        = "system"
  priority    = "100"
  datacenters = ["dc1"]
  # namespace   = "ops"
  namespace = "default"

  update {
    canary            = 1
    max_parallel      = 2
    health_check      = "checks"
    min_healthy_time  = "10s"
    healthy_deadline  = "5m"
    progress_deadline = "10m"
    auto_revert       = true
    auto_promote      = true
    stagger           = "30s"
  }

  group "system" {
    count = 1
    network {
      port "http" {}
      port "grpc" {}
    }

    service {
      port = "http"
      tags = ["monitoring", "grafana"]
      check {
        name     = "alloy-healthy"
        type     = "http"
        path     = "/-/healthy"
        interval = "10s"
        timeout  = "5s"
      }
      check {
        name     = "alloy-ready"
        type     = "http"
        path     = "/-/ready"
        interval = "10s"
        timeout  = "5s"
      }
    }

    task "alloy" {
      vault {}
      identity {
        name = "alloy-system"
        aud  = ["vault.io"]
        ttl  = "1h"
      }
      resources {
        cpu    = 250 # 250 MHz
        memory = 150 # 150MB
      }
      template {
        # data          = file("templates/config.loki.alloy")
        data        = <<EOF
local.file_match "consul_logs" {
  path_targets = [ { "__path__" = "/home/consul/consul*.log", "job" = "consul", "hostname" = "constants.hostname" } ]
}

loki.source.file "log_scrape" {
  targets = local.file_match.consul_logs.targets
  forward_to = [ loki.write.local.receiver ]
  tail_from_end = true
}
{{ range service "loki" }}
loki.write "local" {
  endpoint {
    url = "http://{{ .Address }}:{{ .Port }}/loki/api/v1/push"
  }
}
{{ end }}
EOF
        destination = "local/loki.config.alloy"
        perms       = "0666"
        change_mode = "restart"
      }
      driver = "raw_exec"
      config {
        command = "local/alloy"
        args    = ["run", "--server.http.listen-addr=${NOMAD_ADDR_http}", "local"]
      }
      artifact {
        source      = "https://github.com/grafana/alloy/releases/download/v1.10.0/alloy-linux-${attr.cpu.arch}.zip"
        destination = "local/alloy"
        mode        = "file"
      }
    }
  }
}
