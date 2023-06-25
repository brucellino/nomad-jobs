auth_enabled: false

server:
  http_listen_port: {{ env "NOMAD_PORT_http" }}
  grpc_listen_port: {{ env "NOMAD_PORT_grpc" }}
  register_instrumentation: true
  http_server_read_timeout: "40s"
  http_server_write_timeout: "50s"
distributor:
  ring:
    kvstore:
      store: consul
      prefix: loki/collectors
ingester:
  lifecycler:
#    {{/* address: loki-grpc.service.consul */}}
    ring:
      kvstore:
        store: consul
        prefix: loki/collectors
      replication_factor: 1
    final_sleep: 0s
  chunk_idle_period: 1m
  chunk_retain_period: 30s
schema_config:
  configs:
    - from: 2020-01-01
      store: aws
      object_store: s3
      schema: v11
      index:
        prefix: loki_

storage_config:
  aws:
    region: ams3
    endpoint:  {{ with secret "hashiatho.me-v2/loki_logs_bucket" }}"https://{{ .Data.data.account_id }}{{ end }}
    bucketnames: {{ key "jobs/loki/logs_bucket" }}
    access_key_id: {{ with secret "hashiatho.me-v2/loki_logs_bucket" }}{{ .Data.data.access_key_id }}{{ end }}
    secret_access_key: {{ with secret "hashiatho.me-v2/loki_logs_bucket" }}{{ .Data.data.secret_access_key }}{{ end }}
    s3forcepathstyle: true
    insecure: false
    dynamodb:
      dynamodb_url: inmemory:///index
  boltdb_shipper:
    active_index_directory: /loki/index
    cache_location: /loki/index_cache
    shared_store: s3
ruler:
  storage:
    s3:
      bucketnames: {{ key "jobs/loki/logs_bucket" }}
