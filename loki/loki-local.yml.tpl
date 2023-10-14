auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s
  chunk_idle_period: 5m
  chunk_retain_period: 30s

schema_config:
  configs:
  - from: 2020-05-15
    store: boltdb-shipper
    object_store: filesystem
    schema: v11
    index:
      prefix: index_
      period: 168h

storage_config:
  boltdb-shipper:
    active_index_directory: /data/loki/index
    build_per_tenant_index: true
    cache_location: /data/botdb-cache
    directory: /data/loki/index
    shared_store: cloudflare
  tsdb_shipper:
  active_index_directory: /data/tsdb-index
  cache_location: /data/tsdb-cache
  shared_store: cloudflare

  filesystem:
    directory: /tmp/loki/chunks

query_scheduler:
  max_outstanding_requests_per_tenant: 32768

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h
