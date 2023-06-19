---
global:
  scrape_interval:     20s
  evaluation_interval: 60s
remote_write:
  - url: http://{{ env "NOMAD_ADDR_prometheus_ui" }}/api/v1/push

scrape_configs:
  - job_name: prometheus
    honor_labels: true
    static_configs:
      - targets: ["{{ env "NOMAD_ADDR_prometheus_ui" }}"]

  rule_files:
  - 'node-rules.yml'
scrape_configs:
  - job_name: 'github_exporters'
    static_configs:
      - targets:
        {{ range service "github-exporter-AAROC-main" }}
          - {{ .Address }}:{{ .Port }}
        {{ end }}
      - targets:
        {{ range service "github-exporter-personal-main" }}
          - {{ .Address }}:{{ .Port }}
        {{ end }}
      - targets:
        {{ range service "github-exporter-hah-main" }}
          - {{ .Address }}:{{ .Port }}
        {{ end }}
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
  - job_name: exporters
    consul_sd_configs:
      - server: localhost:8500
        services:
          - github-exporter-AAROC-main
