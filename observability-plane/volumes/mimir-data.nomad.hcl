# Host volume for Mimir data storage
type      = "host"
volume_id = "mimir-storage"
name      = "mimir-storage"
node_id   = "2e522eaf-8518-b236-e3ce-ecc414d0ee5e"
plugin_id = "mkdir"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

capacity_max = "10GB"
