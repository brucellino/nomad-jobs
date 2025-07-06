job "webserver" {
  datacenters = ["dc1"]
  type        = "service"
  spread {
    attribute = "${attr.consul.dns.addr}"
  }
  group "webserver" {
    count = 3
    network {
      port "http" {
        to = 80
      }
    }

    volume "cache-volume" {
      type            = "csi"
      source          = "jfs"
      attachment_mode = "file-system"
      access_mode     = "multi-node-multi-writer"
    }

    service {
      name = "apache-webserver"
      tags = ["urlprefix-/"]
      port = "http"
      check {
        name     = "alive"
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
    }

    restart {
      attempts = 2
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    task "apache" {

      driver = "docker"
      config {
        image = "httpd:latest"
        ports = ["http"]
      }
      resources {
        cpu    = 256
        memory = 256
      }
      volume_mount {
        volume      = "cache-volume"
        destination = "/var/log/httpd"
      }
    }
  }
}
