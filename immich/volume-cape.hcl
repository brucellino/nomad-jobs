# Postgres volume for immich on cape
type      = "host"
name      = "immich-db"
plugin_id = "mkdir"
node_id = "6a35c216-e0b3-ce37-adf0-7d44bb036e3f"
capacity = "2GB"
capacity_max = "2GB"
capacity_min = "512mB"
parameters = {
  mode = "0777"
  # uid  = 1000
  # gid  = 1000
}

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

capability {
  access_mode     = "single-node-single-writer"
  attachment_mode = "file-system"
}

capability {
  access_mode     = "single-node-reader-only"
  attachment_mode = "file-system"
}
