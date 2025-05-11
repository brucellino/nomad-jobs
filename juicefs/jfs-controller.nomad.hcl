job "jfs-controller" {
  datacenters = ["dc1"]
  type        = "system"
  namespace   = "ops"
  constraint {
    attribute = "${attr.driver.docker.privileged.enabled}"
    value     = "true"
  }
  group "controller" {
    task "plugin" {
      driver = "docker"
      config {
        image = "juicedata/juicefs-csi-driver:v0.28.0"

        args = [
          "--endpoint=unix://csi/csi.sock",
          "--logtostderr",
          "--nodeid=test",
          "--v=5",
          "--by-process=true"
        ]
        dns_servers = ["${attr.unique.network.ip-address}", "1.1.1.1"]
        dns_search_domains = [
          "consul",
        ]

        privileged = true
      }

      csi_plugin {
        id        = "juicefs0"
        type      = "controller"
        mount_dir = "/csi"
      }
      resources {
        cpu    = 100
        memory = 512
      }
      env {
        POD_NAME = "csi-controller"
      }
    }
  }
}
