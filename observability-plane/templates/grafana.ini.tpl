{{ with secret "hashiatho.me-v2/observability" }}
[auth.anonymous]
enabled = true

[server]
protocol = http
http_port = ${NOMAD_HOST_PORT_grafana_server}
# cert_file = none
# cert_key = none

[database]
type = postgres
{{- range service "grafana-back-postgres" }}
host = {{ .Address }}:{{ .Port }}
{{- end }}
user = {{ .Data.data.postgres_root_user }}
password = """{{ .Data.data.postgres_root_password }}"""
ssl_mode = disable
log_queries = true
instrument_queries = true
# ca_cert_path = none
# client_key_path = none
# client_cert_path = none
# server_cert_name = none

[paths]
data = /local/data/
logs = /local/log/
plugins = /local/plugins

[analytics]
reporting_enabled = false

[snapshots]
external_enabled = false

[security]
admin_user = admin
admin_password = {{ .Data.data.grafana_admin_password }}
disable_gravatar = true

[dashboards]
versions_to_keep = 10

{{ end }}
