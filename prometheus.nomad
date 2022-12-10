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
        source      = "https://github.com/prometheus/prometheus/releases/download/v2.40.2/prometheus-2.40.2.linux-arm64.tar.gz"
        destination = "local"

        options {
          checksum = "sha256:9f39cf29756106ee4c43fe31d346dcfca58fc275c751dce9f6b50eb3ee31356c"
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
  - job_name: 'nomad_metrics'
    nomad_sd_configs:
      - server: http://nomad.service.consul:4646
EOH
      }

      template {
        change_mode = "restart"
        destination = "local/node-rules.yml"
        left_delimiter = "[["
        right_delimiter = "]]"
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
        command = "local/prometheus-2.40.2.linux-arm64/prometheus"
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
