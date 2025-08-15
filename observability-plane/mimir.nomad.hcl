variable "mimir_version" {
  default     = "2.16.1"
  type        = string
  description = "Version of Mimir to use"
}

variable "mimir_replicas" {
  default     = 1
  type        = number
  description = "Number of Mimir replicas"
}

# Nomad job to run Grafana Mimir for remote Prometheus storage
job "mimir" {
  datacenters = ["dc1"]
  type        = "service"
  priority    = "70"

  update {
    max_parallel      = 1
    health_check      = "checks"
    min_healthy_time  = "30s"
    healthy_deadline  = "5m"
    progress_deadline = "10m"
    canary            = 0
    auto_promote      = false
    auto_revert       = true
    stagger           = "30s"
  }

  migrate {
    max_parallel     = 1
    health_check     = "checks"
    min_healthy_time = "30s"
    healthy_deadline = "10m"
  }

  constraint {
    attribute = attr.cpu.arch
    value     = "arm64"
  }

  group "mimir" {
    count = var.mimir_replicas

    vault {}

    volume "mimir-data" {
      type            = "host"
      source          = "mimir-storage"
      read_only       = false
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    network {
      mode = "bridge"
      port "http" {
        to = 8080
      }
      port "grpc" {
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
      name = "mimir"
      port = "http"
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
      port = "grpc"
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
        volume      = "mimir-data"
        destination = "/data"
        read_only   = false
      }

      config {
        image   = "busybox:1.36"
        command = "sh"
        args = [
          "-c",
          "mkdir -p /data/tsdb-sync /data/compactor && chown -R 10001:10001 /data && chmod -R 755 /data"
        ]
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }

    task "mimir" {
      driver = "docker"

      volume_mount {
        volume      = "mimir-data"
        destination = "/data"
        read_only   = false
      }

      config {
        image = "grafana/mimir:${var.mimir_version}"
        ports = ["http", "grpc"]

        args = [
          "-config.file=/local/mimir.yaml",
          "-target=all"
        ]
      }

      # vault {
      #   policies = ["mimir-policy"]
      # }

      template {
        data        = file("./templates/mimir.yaml")
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
