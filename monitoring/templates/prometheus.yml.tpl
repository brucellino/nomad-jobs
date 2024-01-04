---
global:
  scrape_interval:     20s
  evaluation_interval: 60s
remote_write:
  - url: http://localhost:9999/mimir/api/v1/push
rule_files:
  - 'node-rules.yml'
scrape_configs:
  - job_name: prometheus
    honor_labels: true
    static_configs:
      - targets: ["{{ env "NOMAD_ADDR_prometheus_ui" }}"]
  - job_name: 'instance_metrics'
    static_configs:
      - targets:
          {{ range service "node-exporter" }}
          - {{ .Address}}:{{ .Port }}
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
    metrics_path: /metrics
    params:
      format: ['prometheus']
  - job_name: nomad_metrics
    params:
      format:
        - prometheus
    scrape_interval: 5s
    scrape_timeout: 5s
    metrics_path: /v1/metrics
    scheme: https
    consul_sd_configs:
      - server: localhost:8500
        datacenter: dc1
        tag_separator: ','
        scheme: http
        services:
          - nomad-client
          - nomad
        tls_config:
          insecure_skip_verify: true
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
