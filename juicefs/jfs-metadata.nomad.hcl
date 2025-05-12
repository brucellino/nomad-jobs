job "jfs-metadata" {
  datacenters = ["dc1"]
  namespace   = "ops"
  priority    = 80
  type        = "service"
  meta {
    auto-backup      = true
    backup-schedule  = "@hourly"
    backup-target-db = "postgres"
  }
  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "arm64"
  }

  update {
    max_parallel      = 1
    min_healthy_time  = "10s"
    healthy_deadline  = "3m"
    progress_deadline = "10m"
    auto_revert       = false
    auto_promote      = true
    canary            = 1
  }
  migrate {
    max_parallel     = 1
    health_check     = "checks"
    min_healthy_time = "10s"
    healthy_deadline = "5m"
  }
  group "redis" {
    count = 1
    network {
      port "redis" {
        to = 6379
      }
    }

    service {
      name = "jfs-metadata"
      tags = ["jfs", "cache"]
      port = "redis"

      check {
        name     = "alive"
        type     = "tcp"
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

    ephemeral_disk {
      sticky  = true
      migrate = true
      size    = 300
    }

    task "redis" {
      driver = "docker"
      vault {}
      identity {
        name = "vault_default"
        aud  = ["vault.io"]
        ttl  = "1h"
      }
      config {
        image = "public.ecr.aws/ubuntu/redis:latest"
        ports = ["redis"]
      }
      template {
        data        = <<-EOF
{{ with secret "hashiatho.me-v2/infra/juicefs" }}
REDIS_PASSWORD={{ .Data.data.metadata_server_root_password }}
{{ end }}
TZ="Europe/Rome"
        EOF
        env         = true
        destination = "secrets/.env"
      }


      logs {
        max_files     = 10
        max_file_size = 15
      }
      resources {
        cpu    = 50
        memory = 125
      }
    }
  }
}
