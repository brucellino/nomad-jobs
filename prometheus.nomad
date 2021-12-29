job "prometheus" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.cpu.modelname}"
    value     = "ARMv7 Processor rev 3 (v7l)"
  }

  group "monitoring" {
    count = 1

    network {
      port "prometheus_ui" {
        static = 9090
      }
    }

    restart {
      attempts = 1
      interval = "5m"
      delay    = "15s"
      mode     = "fail"
    }

    ephemeral_disk {
      size = 300
    }

    task "prometheus" {
      artifact {
        source      = "https://github.com/prometheus/prometheus/releases/download/v2.32.1/prometheus-2.32.1.linux-armv7.tar.gz"
        destination = "local"

        options {
          checksum = "sha256:21d8a095f02b2986d408cff744e568ca66c92212b124673143b155a80284d2e4"
        }
      }

      template {
        change_mode = "noop"
        destination = "local/webserver_alert.yml"

        data = <<EOH
---
groups:
- name: prometheus_alerts
  rules:
  - alert: Webserver down
    expr: absent(up{job="webserver"})
    for: 10s
    labels:
    severity: critical
    annotations:
        description: "Our webserver is down."
    EOH
      }

      template {
        change_mode = "noop"
        destination = "local/prometheus.yml"

        data = <<EOH
---
global:
  scrape_interval:     5s
  evaluation_interval: 5s

scrape_configs:
  - job_name: 'instance_metrics'
    static_configs:
      - targets:
          {{ range nodes }}
          - {{ .Address}}:9100
          {{ end }}
  - job_name: 'nomad_metrics'
    consul_sd_configs:
    - server: '{{ env "CONSUL_HTTP_ADDR" }}'
      services: ['nomad-client', 'nomad']
    relabel_configs:
    - source_labels: ['__meta_consul_tags']
      regex: '(.*)http(.*)'
      action: keep
    scrape_interval: 5s
    metrics_path: /v1/metrics
    params:
      format: ['prometheus']
EOH
      }

      driver = "raw_exec"

      config {
        command = "local/prometheus-2.32.1.linux-armv7/prometheus"
        args    = ["--config.file=local/prometheus.yml"]
      }

      resources {
        cpu = 2000
        memory = 2000
      }

      service {
        name = "prometheus"
        tags = ["urlprefix-/"]
        port = "prometheus_ui"

        check {
          name     = "prometheus_ui port alive"
          type     = "http"
          path     = "/-/healthy"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
