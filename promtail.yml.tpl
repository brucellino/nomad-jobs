server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

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
