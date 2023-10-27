job "nginx" {
  datacenters = ["dc1"]
  update {
    max_parallel      = 2
    health_check      = "checks"
    min_healthy_time  = "10s"
    healthy_deadline  = "5m"
    progress_deadline = "10m"
    auto_revert       = true
    auto_promote      = true
    canary            = 1
    stagger           = "30s"
  }
  migrate {
    max_parallel     = 1
    health_check     = "checks"
    min_healthy_time = "10s"
    healthy_deadline = "5m"
  }
  group "nginx" {
    count = 1

    network {
      mode = "bridge"
      port "http" { static = 80 }
    }

    service {
      name = "nginx"
      port = "http"
      // connect {
      //   sidecar_service {
      //     disable_default_tcp_check = true
      //   }
      // }
      check {
        name     = "nginx_alive"
        type     = "tcp"
        interval = "10s"
        timeout  = "1s"
      }

      check {
        name     = "nginx_http_alive"
        type     = "http"
        port     = "http"
        path     = "/nginx_status"
        interval = "5s"
        timeout  = "2s"
      }
    }

    task "nginx" {
      driver = "docker"
      resources {
        cpu    = 1000
        memory = 512
      }
      config {
        image = "nginx:stable-alpine-slim"
        // privileged = true
        ports        = ["http"]
        network_mode = "bridge"
        volumes = [
          "local:/etc/nginx/conf.d",
        ]
      }

      template {
        data          = <<EOF
upstream backend {
{{ range service "promtail" }}
  server {{ .Address }}:{{ .Port }};
{{ else }}server 127.0.0.1:65535; # force a 502
{{ end }}
}

server {
  listen 80;
  location /nginx_status {
    stub_status on;
    allow 127.0.0.1;
  }
  location /promtail {
    proxy_pass http://backend;
  }
}
EOF
        destination   = "local/load-balancer.conf"
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }
    }
  }
}
