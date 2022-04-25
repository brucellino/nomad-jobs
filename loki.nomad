variable "loki_version" {
  type = string
  default = "v2.5.0"
  description = "Loki release to deploy. See https://github.com/grafana/loki/releases/"
}
job "loki" {
  datacenters = ["dc1"]
  type = "service"
  name = "loki"
  // migrate {}
  priority = 80
  group "log-server" {
    network {
      port "loki_http_listen" {
        static = 3100
      }
      port "loki_grpc_listen" {
        static = 9096
      }
      port "promtail_http_listen" {
        static = 9080
      }
      port "promtail_grpc_listen" {
        static = 0
      }
    }
    service {
      name = "loki-http-server"
      tags = ["logs", "loki", "observability"]
      port = "loki_http_listen"

      check {
        name = "loki_http_alive"
        type = "tcp"
        interval = "10s"
        timeout = "3s"
      }
    }
    task "server" {
      driver = "raw_exec"
      config {
        command = "loki"
        args = [
          "-config.file=local/loki.yml"
        ]
      }
      template {
        source = "local/loki.yml.tpl"
        destination = "local/loki.yml"
      }
      // artifact {
      //   source = "https://github.com/grafana/loki/releases/download/${var.loki_version}/loki-linux-${attr.cpu.arch}.zip"
      //   options { # checksum depends on the cpu arch
      //   }
      //   destination = "local/loki"
      //   mode = "file"
      // }
      artifact {
        source = "http://minio-deploy-run.service.consul:9000/loki-bin/loki-linux-${attr.cpu.arch}.zip"
        destination = "local/loki"
        mode = "file"
      }
      artifact {
        source = "http://minio-deploy-run.service.consul:9000/loki-config/loki.hcl.tpl"
        destination = "local/loki.yml.tpl"
        mode = "file"
      }

    }

  }
}
