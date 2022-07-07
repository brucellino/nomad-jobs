job "prometheus" {
  datacenters = ["dc1"]
  type        = "service"
  meta {
    auto-backup = true
    backup-schedule = "@daily"
    backup-target-db = "postgres"
  }
  update {
    max_parallel = 1
    health_check = "checks"
    canary = 1
    auto_promote = true
    auto_revert = true
  }

  constraint {
     attribute = attr.cpu.arch
     value     = "arm64"
  }

  group "monitoring" {
    count = 2

    network {
      port "prometheus_ui" {
        static = 9090
      }
    }

    restart {
      attempts = 2
      interval = "5m"
      delay    = "1m"
      mode     = "fail"
    }

    ephemeral_disk {
      size = 300
    }

    task "prometheus" {
      artifact {
        source      = "https://github.com/prometheus/prometheus/releases/download/v2.36.2/prometheus-2.36.2.linux-arm64.tar.gz"
        destination = "local"

        options {
          checksum = "sha256:302abfe197f40572b42c7b765f1a37beb7272f985165e5769519fe0a789dcc98"
        }
      }
      template {
        change_mode = "restart"
        destination = "local/prometheus.yml"
        data = <<EOH
---
global:
  scrape_interval:     20s
  evaluation_interval: 60s

scrape_configs:
  - job_name: 'instance_metrics'
    static_configs:
      - targets:
          {{ range nodes }}
          - {{ .Address}}:9100
          {{ end }}
  - job_name: 'consul_metrics'
    consul_sd_configs:
      - server: consul.service.consul:8500
        services:
          {{ range services }}
          - {{ .Name }}
          {{ end }}
    relabel_configs:
      - source_labels: [__meta_consul_tags]
        separator: ;
        regex: (.*)http(.*)
        replacement: $1
        action: keep
      - source_labels: [__meta_consul_address]
        separator: ;
        regex: (.*)
        target_label: __meta_consul_service_address
        replacement: $1
        action: replace
    scrape_interval: 5s
    metrics_path: /v1/metrics
    params:
      format: ['prometheus']
EOH
      }

      driver = "exec"

      config {
        command = "local/prometheus-2.36.2.linux-arm64/prometheus"
        args    = [
          "--config.file=local/prometheus.yml",
          "--web.external-url=http://0.0.0.0:9090/prometheus"
          ]
      }

      resources {
        cpu = 250
        memory = 400
      }

      service {
        name = "prometheus"
        tags = ["urlprefix-/prometheus"]
        port = "prometheus_ui"

        check {
          name     = "prometheus_ui port alive"
          type     = "http"
          path     = "prometheus/-/healthy"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
