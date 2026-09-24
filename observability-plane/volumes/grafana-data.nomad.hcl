# Dynamic host volume specification for Grafana data storage
# This creates a persistent volume for Grafana's database, dashboards, plugins, and other data
# Grafana requires write access to store its SQLite database, user sessions, and dashboard definitions

namespace = "default"
name      = "grafana-storage"
type      = "host"
node_id   = "f5f14e33-92f1-5504-b434-fe12a7e04b57"

# mkdir is the default built-in plugin that creates directories on the host
plugin_id = "mkdir"

# Single-node-writer ensures data consistency for Grafana's SQLite database
# Only one Grafana instance can mount this volume at a time
capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

# Mount options to set proper ownership for Grafana user (UID 472, GID 0)
# Grafana runs as user 472 in the official Docker image
mount_options {
  mount_flags = ["uid=472", "gid=0"]
}

# Maximum capacity allocation for Grafana data
# Includes space for:
# - SQLite database
# - Dashboard JSON files
# - User preferences
# - Plugins
# - Temporary files and caches
capacity_max = "5GB"

# Context information for volume management
context {
  purpose = "grafana-persistent-data"
  backup  = "recommended"
}
