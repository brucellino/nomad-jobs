# Do not use this configuration in production.
# It is for demonstration purposes only.
multitenancy_enabled: false
{{ with secret "hashiatho.me-v2/mimir_bucket" }}
common:
  storage:
    backend: s3
    s3:
      endpoint: beb61125927ff6f81b508dec6fdfdfa2.r2.cloudflarestorage.com
      region: auto
      secret_access_key: {{ .Data.data.secret_access_key }}
      access_key_id: {{ .Data.data.access_key_id }}
blocks_storage:
  s3:
    bucket_name: prometheus-mimir
  backend: s3
  bucket_store:
    sync_dir: /tmp/mimir/tsdb-sync
  filesystem:
    dir: /tmp/mimir/data/tsdb
  tsdb:
    dir: /tmp/mimir/tsdb

compactor:
  data_dir: /tmp/mimir/compactor
  sharding_ring:
    kvstore:
      store: memberlist

distributor:
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: memberlist

ingester:
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: memberlist
    replication_factor: 1

ruler_storage:
  s3:
    bucket_name: mimir-ruler
  backend: s3
  filesystem:
    dir: /tmp/mimir/rules

server:
  http_listen_port: 9009
  log_level: error

store_gateway:
  sharding_ring:
    replication_factor: 1
{{ end }}
