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
    address: 127.0.0.1
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
    - from: 2022-01-01
      store: boltdb-shipper
      object_store: filesystem
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

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h

compactor:
  working_directory: local/data/compactor
  shared_store: filesystem
  compaction_interval: 5m
