server:
  log_level: info
  http_listen_port: 9080
  grpc_listen_port: 9095

positions:
  filename: /data/positions.yaml

clients:
  - url: http://loki-http-server.service.consul:3100/loki/api/v1/push

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
    max_age: 12h
    path: /var/log/journal
    matches: _TRANSPORT
    labels:
      job: systemd-journal
  relabel_configs:
  - source_labels: ['__journal__systemd_uinit']
    target_label: 'unit'
  - source_labels: ['__journal_syslog_identifier']
    target_label: 'syslog_identifier'
