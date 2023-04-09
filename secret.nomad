job "secret-example" {
  datacenters = ["dc1"]
  type = "service"
  update {
    max_parallel = 1
    min_healthy_time = "10s"
    healthy_deadline = "3m"
    progress_deadline = "10m"
    auto_revert = false
    canary = 0
  }
  migrate {
    max_parallel = 1
    health_check = "checks"
    min_healthy_time = "10s"
    healthy_deadline = "5m"
  }
  group "mysql" {
    count = 1
    network {
      port "db" {
        to = 3306
      }
    }
    service {
        name = "mysql"
        tags = ["mysql", "active"]
        port = "db"

        // check {
        //   name     = "alive"
        //   type     = "tcp"
        //   interval = "10s"
        //   timeout  = "2s"
        // }
      }

    restart {
      # The number of attempts to run the job within the specified interval.
      attempts = 2
      interval = "30m"
      delay = "15s"
      mode = "fail"
    }

    ephemeral_disk {
      size = 160
    }

    task "server" {
      driver = "docker"
      config {
        image = "public.ecr.aws/lts/mysql:8.0-22.04_edge"
        ports = ["db"]
      }
      env {
        MYSQL_ROOT_PASSWORD = "test" # pragma: allowlist secret
        MYSQL_PASSWORD = "test" # pragma: allowlist secret
        MYSQL_USER = "hashi"
        MYSQL_DATABASE = "hashi_db"
      }


      logs {
        max_files     = 10
        max_file_size = 15
      }

      resources {
        cpu    = 125
        memory = 100
      }

      template {
        data          = <<EOF
---
key: "{{ key "hashiatho.me/jobs/mysql/version" }}"
secret: "{{ with secret "hashiatho.me-v2/data/r2_cli"}}{{ .Data.data.access_key_id }}{{ end }}"
EOF
        destination   = "local/file.yml"
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }

      vault {
        policies      = ["nomad-read"]
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }

      # Controls the timeout between signalling a task it will be killed
      # and killing the task. If not set a default is used.
      # kill_timeout = "20s"
    }
  }
}
