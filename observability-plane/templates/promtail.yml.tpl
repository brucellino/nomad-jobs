server:
  log_level: info
  http_listen_address: {{ env "NOMAD_IP_http" }}
  http_listen_port: {{ env "NOMAD_PORT_http" }}
  grpc_listen_port: {{ env "NOMAD_PORT_grpc" }}

positions:
  filename: /data/positions.yaml
{{ range service "loki-http-server" }}
clients:
  - url: http://{{ .Address }}:{{ .Port }}/loki/api/v1/push
{{ end }}
scrape_configs:
  - job_name: vault
    static_configs:
      - targets:
          - localhost
        labels:
          job: vault-server
          __path__: /var/log/vault.log
      - targets:
          - localhost
        labels:
          job: vault-agent
          __path__: /var/log/vault-agent.log
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
  - job_name: Nomad Jobs
    static_configs:
    - targets:
        - localhost
      labels:
        job: nomad_allocations
        __path__: /opt/nomad/alloc/*/*/alloc/logs/*
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
