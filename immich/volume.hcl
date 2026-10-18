# Postgres volume for immich on ticklish
type      = "host"
name      = "immich-db"
plugin_id = "mkdir"
node_id = "fadbd137-dd3a-5dfc-49ce-242116ec4fd9"
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
