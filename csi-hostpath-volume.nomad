id           = "consul-data"
namespace    = "default"
name         = "consul-data"
type         = "csi"
plugin_id    = "csi-hostpath"
external_id  = "consul-data"
capacity_max = "1G"
capacity_min = "100M"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

mount_options {
  fs_type     = "ext4"
  mount_flags = ["noatime"]
}
