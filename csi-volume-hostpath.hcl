id        = "grafana"
name      = "grafana"
type      = "csi"
plugin_id = "csi-hostpath"

capacity_min = "1MB"
capacity_max = "1GB"

capability {
  access_mode     = "single-node-reader-only"
  attachment_mode = "file-system"
}
capability {
  access_mode     = "multi-node-reader-only"
  attachment_mode = "file-system"
}

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

mount_options {
  mount_flags = ["rw"]
}
