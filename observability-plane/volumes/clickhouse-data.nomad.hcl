# Host volume for Clickhouse Database
type      = "host"
volume_id = "clickhouse-data"
name      = "clickhouse-data"
node_id   = "2e522eaf-8518-b236-e3ce-ecc414d0ee5e"
plugin_id = "mkdir"

parameters = {
  mode = "0755"
  # Looks like the all in one image uses root
  # uid  = 0
  # gid  = 0

}

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

capacity_max = "2GB"
