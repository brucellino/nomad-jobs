# Host volume for Mimir data storage
type      = "host"
volume_id = "grafana-pg-db-pop-os"
name      = "grafana-pg-db"
node_id   = "2e522eaf-8518-b236-e3ce-ecc414d0ee5e"
plugin_id = "mkdir"

parameters = {
  mode = "0755"
  uid  = 70 # Postgres uid in postgres:alpine
  gid  = 70

}

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

capacity_max = "2GB"
