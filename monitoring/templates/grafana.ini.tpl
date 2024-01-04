{{ with secret "hashiatho.me-v2/grafana" }}
[auth.anonymous]
enabled = true

[server]
protocol = http
http_port = ${NOMAD_HOST_PORT_grafana_server}
# cert_file = none
# cert_key = none

[database]
type = mysql
{% comment %} host = mysql.service.consul:3306 {% endcomment %}
{{- range service "mysql" }}host = {{ .Address }}:{{ .Port }}{{- end }}
user = root
password = """{{ .Data.data.root_password }}"""
ssl_mode = disable
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

[alerting]
enabled = true

[unified_alerting]
enabled = true
{{ end }}
