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
