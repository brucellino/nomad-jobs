job "node-exporter" {
  type        = "system"
  priority    = "100"
  datacenters = ["dc1"]
  namespace   = "ops"

  update {
    canary            = 1
    max_parallel      = 2
    health_check      = "checks"
    min_healthy_time  = "10s"
    healthy_deadline  = "5m"
    progress_deadline = "10m"
    auto_revert       = true
    auto_promote      = true
    stagger           = "30s"
  }

  group "system" {
    count = 1
    network {
      port "http" {}
      port "grpc" {}
    }

    service {
      port = "http"
      tags = ["monitoring", "grafana"]
      check {
        name     = "alloy-healthy"
        type     = "http"
        path     = "/-/healthy"
        interval = "10s"
        timeout  = "5s"
      }
      check {
        name     = "alloy-ready"
        type     = "http"
        path     = "/-/ready"
        interval = "10s"
        timeout  = "5s"
      }
    }

    task "alloy" {
      vault {}
      identity {
        name = "alloy-system"
        aud  = ["vault.io"]
        ttl  = "1h"
      }
      resources {
        cpu    = 250 # 250 MHz
        memory = 150 # 150MB
      }
      template {
        data          = file("templates/config.alloy")
        destination   = "local/config.alloy"
        perms         = "0666"
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }
      driver = "raw_exec"
      config {
        command = "local/alloy"
        args    = ["run", "--server.http.listen-addr=${NOMAD_ADDR_http}", "local"]
      }
      artifact {
        source      = "https://github.com/grafana/alloy/releases/download/v1.8.3/alloy-linux-${attr.cpu.arch}.zip"
        destination = "local/alloy"
        mode        = "file"
      }
    }
  }
}
