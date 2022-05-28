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
  #vault {
  #      policies = ["nomad-monitoring"]
  #      // entity_alias = "prometheus"
  #}
  constraint {
     attribute = attr.cpu.arch
     value     = "arm64"
  }

  group "monitoring" {
    count = 1

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
        source      = "https://github.com/prometheus/prometheus/releases/download/v2.35.0/prometheus-2.35.0.linux-arm64.tar.gz"
        destination = "local"

        options {
          checksum = "sha256:3ebe0c533583a9ab03363a80aa629edd8e0cc42da3583e33958eb7abe74d4cd2"
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
  - job_name: vault
    metrics_path: /v1/sys/metrics
    params:
      format: ['prometheus']
    scheme: http
    authorization:
      credentials: '"${env["VAULT_TOKEN"]}"'
    static_configs:
      - targets: ['vault.service.consul:8200']
  - job_name: 'instance_metrics'
    static_configs:
      - targets:
          {{ range nodes }}
          - {{ .Address}}:9100
          {{ end }}
  - job_name: 'consul_metrics'
    consul_sd_configs:
    - server: sense:8500
      services:
        {{ range services }}
        - {{ .Name }}
        {{ end }}
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

      driver = "exec"

      config {
        command = "local/prometheus-2.35.0.linux-arm64/prometheus"
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
