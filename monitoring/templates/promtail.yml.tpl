server:
  log_level: info
  http_listen_port: {{ env "NOMAD_PORT_http" }}
  grpc_listen_port: {{ env "NOMAD_PORT_grpc" }}

positions:
  filename: /data/positions.yaml

clients:
  - url: http://localhost:9999/loki/loki/api/v1/push

scrape_configs:
  - job_name: consul
    static_configs:
    - targets:
        - localhost
      labels:
        job: consul
        __path__: /home/consul/*.log
  - job_name: nomad
    static_configs:
    - targets:
        - localhost
      labels:
        job: nomad
        __path__: /var/log/nomad*.log
  - job_name: journal
    journal:
      json: false
      max_age: 12h
      path: /var/log/journal
      matches: _TRANSPORT=kernel
      labels:
        job: systemd-journal
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        target_label: 'unit'
      - source_labels: ['__journal_syslog_identifier']
        target_label: 'syslog_identifier'
      - source_labels:
          - __journal__hostname
        target_label: nodename
