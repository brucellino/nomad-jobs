{{/*
  Read the Loki Logs bucket secret. This will have scope throughout the template.
  See the end of the template for the closing statement.
*/}}
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
    address: {{ env "NOMAD_IP_http" }}
    port: {{ env "NOMAD_PORT_http" }}
    ring:
      kvstore:
        store: consul
        prefix: loki/collectors
      replication_factor: 1
    final_sleep: 0s
  chunk_idle_period: 5m
  chunk_retain_period: 30s
  flush_op_timeout: 20m
schema_config:
  configs:
{{/*
    store: boltdb-shipper
    object_store: filesystem
*/}}
    - from: 2022-01-01
      store: boltdb-shipper
      object_store: aws
      schema: v11
      index:
        prefix: loki_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: local/index
    cache_location: local/index_cache
  filesystem:
    directory: local/index
  aws:
    bucketnames: hah-logs
    endpoint: {{ .Data.data.account_id }}.r2.cloudflarestorage.com
    region: auto
    access_key_id: {{ .Data.data.access_key_id }}
    secret_access_key: {{ .Data.data.secret_access_key }}
    insecure: false
    sse_encryption: false
    http_config:
      idle_conn_timeout: 90s
      insecure_skip_verify: false
    s3forcepathstyle: true
    dynamodb:
      dynamodb_url: inmemory

limits_config:
  enforce_metric_name: false
  reject_old_samples: false
  reject_old_samples_max_age: 168h

compactor:
  working_directory: local/data/compactor
  shared_store: filesystem
  compaction_interval: 5m
{{ end }}
