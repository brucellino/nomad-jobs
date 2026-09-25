variable "prometheus_version" {
  default     = "3"
  type        = string
  description = "Version of Prometheus to use"
}

variable "mimir_version" {
  default     = "2.16.1"
  type        = string
  description = "Version of Mimir to use"
}


# Nomad job for metrics
# runs Prometheus and Mimir with remote write
job "metrics" {
  datacenters = ["dc1"]
  type        = "service"
  priority    = "60"

  update {
    max_parallel      = 1
    health_check      = "checks"
    min_healthy_time  = "30s"
    healthy_deadline  = "5m"
    progress_deadline = "10m"
    canary            = 1
    auto_promote      = true
    auto_revert       = true
    stagger           = "30s"
  }

  migrate {
    max_parallel     = 1
    health_check     = "checks"
    min_healthy_time = "30s"
    healthy_deadline = "10m"
  }

  # Both are servers, we create one group for both mimir and prometheus.
  group "srv" {
    count = 1

    vault {}

    # We may not need prometheus data if we are writing to mimir
    volume "prometheus-data" {
      type            = "host"
      source          = "prometheus-storage"
      read_only       = false
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    volume "mimir-data" {
      type            = "host"
      source          = "mimir-storage"
      read_only       = false
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    network {
      port "prom_http" {
        to = 9090
      }
      port "mimir_http" {
        to = 8080
      }
      port "mimir_grpc" {
        to = 9095
      }
    }

    restart {
      attempts = 3
      interval = "10m"
      delay    = "30s"
      mode     = "delay"
    }

    reschedule {
      delay          = "5m"
      delay_function = "fibonacci"
      unlimited      = true
    }

    service {
      name = "prometheus"
      port = "prom_http"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.prometheus.rule=PathPrefix(`/prometheus`)",
        "traefik.http.routers.prometheus.middlewares=prometheus-stripprefix",
        "traefik.http.middlewares.prometheus-stripprefix.stripprefix.prefixes=/prometheus"
      ]

      check {
        name     = "prometheus-ready"
        type     = "http"
        path     = "/-/ready"
        interval = "10s"
        timeout  = "3s"
      }

      check {
        name     = "prometheus-healthy"
        type     = "http"
        path     = "/-/healthy"
        interval = "30s"
        timeout  = "3s"
      }

      check {
        name     = "prometheus-metrics"
        type     = "http"
        path     = "/metrics"
        interval = "30s"
        timeout  = "3s"
      }
    }

    service {
      name = "mimir"
      port = "mimir_http"
      tags = [
        "mimir",
        "metrics",
        "storage",
        "prometheus",
        "traefik.enable=true",
        "traefik.http.routers.mimir.rule=PathPrefix(`/mimir`)",
        "traefik.http.routers.mimir.middlewares=mimir-stripprefix",
        "traefik.http.middlewares.mimir-stripprefix.stripprefix.prefixes=/mimir"
      ]

      check {
        name     = "mimir-ready"
        type     = "http"
        path     = "/ready"
        interval = "10s"
        timeout  = "3s"
      }

      check {
        name     = "mimir-config"
        type     = "http"
        path     = "/config"
        interval = "30s"
        timeout  = "3s"
      }

      check {
        name     = "mimir-metrics"
        type     = "http"
        path     = "/metrics"
        interval = "30s"
        timeout  = "3s"
      }
    }

    service {
      name = "mimir-grpc"
      port = "mimir_grpc"
      tags = [
        "mimir-grpc",
        "metrics-grpc"
      ]

      check {
        name     = "mimir-grpc-health"
        type     = "tcp"
        interval = "10s"
        timeout  = "3s"
      }
    }

    task "init-permissions" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      volume_mount {
        volume      = "prometheus-data"
        destination = "/prometheus"
        read_only   = false
      }

      config {
        image   = "busybox:1.36"
        command = "sh"
        args = [
          "-c",
          "chown -R 65534:65534 /prometheus && chmod -R 755 /prometheus"
        ]
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }

    task "prometheus" {
      driver = "docker"

      volume_mount {
        volume      = "prometheus-data"
        destination = "/prometheus"
        read_only   = false
      }

      config {
        image = "prom/prometheus:v${var.prometheus_version}"
        ports = ["prom_http"]
        # Args
        args = [
          "--config.file=/local/prometheus.yml",
          "--storage.tsdb.path=/prometheus",
          "--storage.tsdb.retention.time=2h",
          "--storage.tsdb.retention.size=1GB",
          "--web.enable-lifecycle",
          "--web.enable-remote-write-receiver",
          "--storage.tsdb.wal-compression",
          "--log.level=info",
          "--log.format=json"
        ]
      }

      kill_timeout = "30s"
      kill_signal  = "SIGTERM"

      template {
        data        = file("./templates/prometheus.yml.tmpl")
        destination = "/local/prometheus.yml"
        change_mode = "restart"
        # left_delimiter = "[["
        # right_delimiter = "]]"
        wait {
          min = "5s"
          max = "30s"
        }
      }

      template {
        data            = file("./templates/prometheus-alerts.yml")
        destination     = "/local/alerts/basic-alerts.yml"
        left_delimiter  = "[["
        right_delimiter = "]]"
        change_mode     = "restart"
        wait {
          min = "5s"
          max = "30s"
        }
      }
      resources {
        cpu    = 512
        memory = 512
      }
      shutdown_delay = "5s"
    }

    task "mimir" {
      leader = true
      driver = "docker"

      volume_mount {
        volume      = "mimir-data"
        destination = "/data"
        read_only   = false
      }

      config {
        image = "grafana/mimir:${var.mimir_version}"
        ports = ["mimir_http", "mimir_grpc"]

        args = [
          "-config.file=/local/mimir.yaml",
          "-target=all"
        ]
      }

      # vault {
      #   policies = ["mimir-policy"]
      # }

      template {
        data        = file("./templates/mimir.yaml.tmpl")
        destination = "/local/mimir.yaml"
        change_mode = "restart"
        wait {
          min = "5s"
          max = "30s"
        }
      }

      resources {
        cpu    = 1000
        memory = 1024
      }

      kill_timeout   = "30s"
      kill_signal    = "SIGTERM"
      shutdown_delay = "5s"
    }
  }
}
