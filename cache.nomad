job "cache" {
  datacenters = ["dc1"]
  type = "service"
  meta {
    auto-backup = true
    backup-schedule = "@daily"
    backup-target-db = "postgres"
  }
  constraint {
     attribute = "${attr.kernel.name}"
     value     = "linux"
  }
  constraint {
    attribute = "${attr.cpu.arch}"
    value = "arm64"
  }

  update {
    max_parallel = 1
    min_healthy_time = "10s"
    healthy_deadline = "3m"
    progress_deadline = "10m"
    auto_revert = false
    canary = 1
  }
  migrate {
    max_parallel = 1
    health_check = "checks"
    min_healthy_time = "10s"
    healthy_deadline = "5m"
  }
  group "cache" {
    count = 1
    volume "REDIS" {
      type = "csi"
      source = "REDIS"
      attachment_mode = "file-system"
      access_mode = "single-node-reader-only"
      read_only = true
      per_alloc = true
    }
    network {
      port "db" {
        to = 6379
      }
    }

    service {
      name = "redis-cache"
      tags = ["global", "cache"]
      port = "db"

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

      delay = "15s"

      mode = "fail"
    }

    ephemeral_disk {
      sticky = true
      migrate = true
      size = 300
    }

    affinity {
      attribute = "${node.datacenter}"
      value  = "dc1"
      weight = 100
    }

    task "redis" {
      # The "driver" parameter specifies the task driver that should be used to
      # run the task.
      driver = "docker"

      config {
        image = "public.ecr.aws/ubuntu/redis:latest"

        ports = ["db"]
      }
      volume_mount {
        volume = "REDIS"
        destination = "${NOMAD_ALLOC_DIR}/volume"
      }
      env {
        TZ = "Europe/Rome"
        REDIS_PASSWORD = "temp"
      }

      logs {
        max_files     = 10
        max_file_size = 15
      }
      resources {
        cpu    = 50 # 500 MHz
        memory = 125 # 256MB
      }
    }
  }
}
