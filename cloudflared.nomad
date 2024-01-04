job "cloudflare-tunnel" {
  datacenters = ["dc1"]
  type        = "service"

  group "app" {
    network {
      port "metrics" {}
      port "cloudflared" {}
      mode = "bridge"
    }
    service {
      name = "cloudflared-test"
      tags = ["cloudflared", "test"]
      port = "cloudflared"
      // check {
      //  name     = "alive"
      //  type     = "tcp"
      //  interval = "10s"
      //  timeout  = "2s"
      // }

      check {
        name     = "metrics"
        type     = "http"
        interval = "10s"
        timeout  = "2s"
        port     = "metrics"
        path     = "/metrics"
      }
    }
    reschedule {
      attempts       = 1
      interval       = "1m"
      unlimited      = false
      delay_function = "constant"
    }
    restart {
      attempts = 1
      interval = "2m"
      delay    = "15s"
      mode     = "delay"
    }

    task "tunnel" {
      vault {}
      template {
        data        = <<EOH
TUNNEL_TOKEN="{{ with secret "hashiatho.me-v2/data/cloudflare" }}{{- .Data.data.cloudflare_access_test_token -}}{{ end }}"
  EOH
        destination = "secrets/.env"
        env         = true
      }
      env {
        TUNNEL_METRICS  = "0.0.0.0:${NOMAD_PORT_metrics}"
        TUNNEL_LOGLEVEL = "info"
      }
      restart {
        interval = "1m"
        attempts = 1
        delay    = "5s"
        mode     = "fail"
      }
      driver = "docker"
      config {
        image = "cloudflare/cloudflared"
        args = [
          "tunnel", "run"
        ]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
