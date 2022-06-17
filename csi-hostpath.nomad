# Add the csi host path plugin
job "plugin-csi-hostpath-controller" {
  datacenters = ["dc1"]
  type = "system"
  group "controller" {
    task "plugin" {
      resources {
        cpu    = 10 # 10 MHz
        memory = 25 # 25MB
      }
      driver = "raw_exec"
      config {
        command = "local/csi-hostpathplugin"
        args = [
          "--drivername=csi-hostpath",
          "--v=5",
          "--endpoint=${CSI_ENDPOINT}",
          "--nodeid=node-${NOMAD_ALLOC_INDEX}"
        ]
      }
      artifact {
        source = "http://minio-api:9000/csi/csi-driver-host-path/bin/hostpathplugin"
        destination = "local/csi-hostpathplugin"
        mode = "file"
      }


      csi_plugin {
        id = "csi-hostpath"
        type = "monolith"
        mount_dir = "/data/csi"
      }
    }
  }
}
