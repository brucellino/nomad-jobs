{{ with secret "hashiatho.me-v2/loki_logs_bucket" }}
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
    - from: "2020-01-01"
      store: aws
      object_store: s3
      schema: v11
      index:
        prefix: loki_
    - from: "2023-10-15"
      index:
        period: 24h
        prefix: index_
      object_store: aws
      schema: v12
      store: tsdb

storage_config:
  aws:
    region: auto
    endpoint:  "https://{{ .Data.data.account_id }}r2.cloudflarestorage.com"
    bucketnames: hah-logs
    access_key_id: {{ .Data.data.access_key_id }}
    secret_access_key: {{ .Data.data.secret_access_key }}
    s3forcepathstyle: true
    insecure: false
    sse_encryption: false
    http_config:
      idle_conn_timeout: 90s
      insecure_skip_verify: false
    dynamodb:
      dynamodb_url: inmemory:///loki
  boltdb_shipper:
    active_index_directory: /data/index
    cache_location: /data/boltdb-cache
    shared_store: aws
    build_per_tenant_index: true
  tsdb_shipper:
    active_index_directory: /data/tsdb-index
    cache_location: /data/tsdb-cache
    shared_store: aws
{{/* ruler:
  storage:
    aws:
      bucketnames: {{ key "jobs/loki/logs_bucket" }} */}}
{{ end }}
