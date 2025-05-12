job "jfs-node" {
  datacenters = ["dc1"]
  type        = "system"
  namespace   = "ops"
  constraint {
    attribute = "${attr.driver.docker.privileged.enabled}"
    value     = "true"
  }
  group "nodes" {
    task "juicefs-plugin" {
      driver = "docker"
      config {
        image = "juicedata/juicefs-csi-driver:v0.27.0"

        args = [
          "--endpoint=unix://csi/csi.sock",
          "--logtostderr",
          "--v=5",
          "--nodeid=test",
          "--by-process=true",
        ]
        dns_servers = ["${attr.unique.network.ip-address}", "1.1.1.1"]
        dns_search_domains = [
          "consul",
        ]
        privileged = true
      }

      csi_plugin {
        id        = "juicefs0"
        type      = "node"
        mount_dir = "/csi"
      }
      resources {
        cpu    = 500
        memory = 512
      }
      env {
        POD_NAME = "csi-node"
      }
    }
  }
}
