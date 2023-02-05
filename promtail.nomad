variable "promtail_version" {
  description = "Version of Promtail to deploy"
  type = string
  default = "v2.7.3"
}

job "promtail" {

  meta {
    auto-backup = true
    backup-schedule = "@daily"
    backup-target-db = "postgres"
  }
  datacenters = ["dc1"]
  type = "system"

  group "promtail" {
    count = 1
    update {
      max_parallel = 3
      canary = 0
      stagger = "30s"
    }
    network {
      port "http" {
        static = 9080
      }
      port "grpc" {
        static = 9095
      }
    }

    service {
      name = "promtail"
      tags = ["http"]
      port = "http"

      check {
        name     = "promtail-alive"
        type     = "tcp"
        interval = "20s"
        timeout  = "15s"
      }

      check {
        name = "Promtail HTTP"
        type = "http"
        path = "/targets"
        interval = "10s"
        timeout = "5s"

        check_restart {
          limit = 2
          grace = "60s"
          ignore_warnings = false
        }
      }
    }

    // service {
    //   name = "promtail-grpc"
    //   tags = ["grpc"]
    //   port = "grpc"

    //   check {
    //     name = "promtail-grpc"
    //     grpc_service = "promtail-grpc"
    //     type = "grpc"
    //     interval = "15s"
    //     timeout = "5s"
    //     port = "grpc"
    //     grpc_use_tls = false
    //     tls_skip_verify = true
    //   }

    // }

    restart {
      attempts = 1
      interval = "10m"
      delay = "15s"
      mode = "delay"
    }

    ephemeral_disk {
      size = 300
    }

    task "promtail" {
      # The "driver" parameter specifies the task driver that should be used to
      # run the task.
      driver = "raw_exec"

      config {
        command = "promtail"
        args = ["-config.file=local/promtail.yml"]
      }

      artifact {
        source = "https://github.com/grafana/loki/releases/download/v2.7.3/promtail-linux-${attr.cpu.arch}.zip"
        destination = "local/promtail"
        mode = "file"
      }


      resources {
        cpu    = 60 # 500 MHz
        memory = 125 # 256MB
      }


      template {
         data          = file("promtail.yml.tpl")
         destination   = "local/promtail.yml"
         change_mode   = "signal"
         change_signal = "SIGHUP"
      }
    }
  }
}
