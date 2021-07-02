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
        to     = 9090
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
        source      = "https://github.com/prometheus/prometheus/releases/download/v2.28.1/prometheus-2.28.1.linux-armv7.tar.gz"
        destination = "local"

        options {
          checksum = "sha256:0ee31e4ee719680143887911dc15e9108ac595fe4345cb1bb959aad5f0281b1a"
        }
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

  - job_name: 'nomad_metrics'

    consul_sd_configs:
    - server: '{{ env "NOMAD_IP_prometheus_ui" }}:8500'
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
        command = "local/prometheus-2.28.1.linux-armv7/prometheus"
        args    = ["--config.file=local/prometheus.yml"]
      }

      resources {}

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
