variable "prom_version" {
  default = "2.43.0"
  type = string
  description = "Version of prometheus to use"
}

variable "prom_sha2" {
  type = string
  default = "cfea92d07dfd9a9536d91dff6366d897f752b1068b9540b3e2669b0281bb8ebf" #pragma: allowlist secret
  description = "https://prometheus.io/download/"
}

job "prometheus" {
  datacenters = ["dc1"]
  type        = "service"
  meta {
    auto-backup = true
    backup-schedule = "@daily"
    backup-target-db = "postgres"
  }
  update {
    max_parallel = 2
    health_check = "checks"
    canary = 1
    auto_promote = true
    auto_revert = true
  }

  constraint {
     attribute = attr.cpu.arch
     value     = "arm64"
  }

  group "server" {
    count = 1
    volume "data" {
      type      = "host"
      read_only = false
      source    = "scratch"
    }
    network {
      port "prometheus_ui" {}
    }

    restart {
      attempts = 1
      interval = "7m"
      delay    = "1m"
      mode     = "fail"
    }

    ephemeral_disk {
      size = 300
    }

    task "prometheus" {
      artifact {
        source      = "https://github.com/prometheus/prometheus/releases/download/v${var.prom_version}/prometheus-${var.prom_version}.linux-arm64.tar.gz"
        destination = "local"

        options {
          checksum = "sha256:${var.prom_sha2}"
        }
      }
      template {
        change_mode = "signal"
        change_signal = "SIGHUP"
        destination = "local/prometheus.yml"
        wait {
          min = "10s"
          max = "20s"
        }
        data = <<EOH
---
global:
  scrape_interval:     20s
  evaluation_interval: 60s
rule_files:
  - 'node-rules.yml'
scrape_configs:
  - job_name: 'instance_metrics'
    static_configs:
      - targets:
          {{ range nodes }}
          - {{ .Address}}:9100
          {{ end }}
  - job_name: 'consul_metrics'
    consul_sd_configs:
      - server: localhost:8500
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

      template {
        change_mode = "noop"
        destination = "local/node-rules.yml"
        left_delimiter = "[["
        right_delimiter = "]]"
        wait {
          min = "10s"
          max = "20s"
        }
        data = <<EOH
---
groups:
  - name: node.rules
    rules:
      - alert: InstanceDown
        expr: up{job="instance_metrics"} == 0
        for: 10m
      - alert: InstancesDown
        expr: avg(up{job="instance_metrics"}) BY (job)
      - alert: HostMemoryUnderMemoryPressure
        expr: rate(node_vmstat_pgmajfault[1m]) > 1000
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: Host memory under memory pressure (instance {{ $labels.instance }})
          description: "The node is under heavy memory pressure. High rate of major page faults\n  VALUE = {{ $value }}\n  LABELS = {{ $labels }}"
      - alert: HostUnusualNetworkThroughputIn
        expr: sum by (instance) (rate(node_network_receive_bytes_total[2m])) / 1024 / 1024 > 100
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: Host unusual network throughput in (instance {{ $labels.instance }})
          description: "Host network interfaces are probably receiving too much data (> 100 MB/s)\n  VALUE = {{ $value }}\n  LABELS = {{ $labels }}"
  - name: prom.rules
    rules:
      - alert: PrometheusJobMissing
        expr: absent(up{job="prometheus"})
        for: 0m
        labels:
          severity: warning
        annotations:
          summary: Prometheus job missing (instance {{ $labels.instance }})
          description: "A Prometheus job has disappeared\n  VALUE = {{ $value }}\n  LABELS = {{ $labels }}"
      - alert: PrometheusTargetMissing
        expr: up == 0
        for: 0m
        labels:
          severity: critical
        annotations:
          summary: Prometheus target missing (instance {{ $labels.instance }})
          description: "A Prometheus target has disappeared. An exporter might be crashed.\n  VALUE = {{ $value }}\n  LABELS = {{ $labels }}"
  - name: consul.rules
    rules:
      - alert: ConsulServiceHealthcheckFailed
        expr: consul_catalog_service_node_healthy == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: Consul service healthcheck failed (instance {{ $labels.instance }})
          description: "Service: `{{ $labels.service_name }}` Healthcheck: `{{ $labels.service_id }}`\n  VALUE = {{ $value }}\n  LABELS = {{ $labels }}"
      - alert: ConsulAgentUnhealthy
        expr: consul_health_node_status{status="critical"} == 1
        for: 0m
        labels:
          severity: critical
        annotations:
          summary: Consul agent unhealthy (instance {{ $labels.instance }})
          description: "A Consul agent is down\n  VALUE = {{ $value }}\n  LABELS = {{ $labels }}"
EOH
      }
      driver = "exec"

      config {
        command = "local/prometheus-${var.prom_version}.linux-arm64/prometheus"
        args    = [
          "--config.file=local/prometheus.yml",
          "--storage.tsdb.retention.size=1GB",
          "--storage.tsdb.retention.time=7d",
          "--web.listen-address=:${NOMAD_PORT_prometheus_ui}",
          "--web.enable-admin-api",
          "--storage.tsdb.path=data"
        ]
      }
      volume_mount {
        volume      = "data"
        destination = "data"
        read_only   = false
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
          name     = "prometheus_readiness check"
          type     = "http"
          path     = "/-/ready"
          interval = "10s"
          timeout  = "2s"
        }
        check {
          name     = "prometheus healthiness check"
          type     = "http"
          path     = "/-/healthy"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
