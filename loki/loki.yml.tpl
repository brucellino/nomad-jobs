auth_enabled: false

server:
  http_listen_port: {{ env "NOMAD_PORT_http" }}
  grpc_listen_port: {{ env "NOMAD_PORT_grpc" }}
memberlist:
  join_members:
    - loki-http-server
schema_config:
  configs:
    - from: 2022-01-01
      store: boltdb-shipper
      object_store: s3
      schema: v11
      index:
        prefix: index_
        period: 24h
common:
  path_prefix: local/
  replication_factor: 1
  storage:
    s3:
      endpoint:  {{ key "jobs/loki/s3_endpoint" }}
      bucketnames: {{ key "jobs/loki/logs_bucket" }}
      access_key_id: {{ env "access_key" }}
      secret_access_key: {{ env "secret_key" }}
      s3forcepathstyle: true
  ring:
    kvstore:
      store: consul
ruler:
  storage:
    s3:
      bucketnames: {{ key "jobs/loki/logs_bucket" }}
