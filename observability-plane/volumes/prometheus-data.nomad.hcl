# Dynamic host volume specification for Prometheus TSDB data storage
# This creates a dynamic host volume that can be claimed by jobs

namespace = "default"
name      = "prometheus-storage"
type      = "host"
node_id   = "2e522eaf-8518-b236-e3ce-ecc414d0ee5e"

# mkdir is the default built-in plugin that creates directories
plugin_id = "mkdir"

# Allows mounting by only one allocation at a time for data consistency
capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

# Mount options to set proper ownership for Prometheus nobody user (65534:65534)
mount_options {
  mount_flags = ["uid=65534", "gid=65534"]
}
