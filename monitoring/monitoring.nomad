variable "prom_version" {
  default     = "2.48.0"
  type        = string
  description = "Version of prometheus to use"
}

variable "prom_sha2" {
  type = map(string)
  default = {
    arm64 : "79c4262a27495e5dff45a2ce85495be2394d3eecd51f0366c706f6c9c729f672" #pragma: allowlist secret
    amd64 : "5871ca9e01ae35bb7ab7a129a845a7a80f0e1453f00f776ac564dd41ff4d754e" #pragma: allowlist secret
  }
  description = "https://prometheus.io/download/"
}

variable "mimir_version" {
  default     = "2.9.3"
  type        = string
  description = "Version of mimir to use"
}

variable "mimir_sha2" {
  type = map(string)
  default = {
    arm64 : "e7d2d401f616b185bded25cfe84f7b6543e169f4d0d8a36e19f7ba124848b712" #pragma: allowlist secret
    amd64 : "3a1aa0ccb97692989433c9087bfc478e21cc6d879637f19f091a4c13778ce441" #pragma: allowlist secret
  }
  description = "See https://github.com/grafana/mimir/releases"
}

variable "grafana_version" {
  type        = string
  default     = "10.2.2"
  description = "Grafana version"
}

job "monitoring" {
  datacenters = ["dc1"]
  type        = "service"
  priority    = "60"
  meta {
    auto-backup      = true
    backup-schedule  = "@daily"
    backup-target-db = "postgres"
  }
  update {
    max_parallel = 2
    health_check = "checks"
    canary       = 1
    auto_promote = true
    auto_revert  = true
  }

  migrate {
    max_parallel     = 1
    health_check     = "checks"
    min_healthy_time = "30s"
    healthy_deadline = "10m"
  }
  constraint {
    attribute = attr.cpu.arch
    value     = "amd64"
  }

  group "prometheus" {
    count = 1
    network {
      port "prometheus_ui" {}
    }

    restart {
      attempts = 1
      interval = "7m"
      delay    = "1m"
      mode     = "fail"
    }

    reschedule {
      delay          = "5m"
      delay_function = "fibonacci"
      unlimited      = true
    }

    ephemeral_disk {
      size = 300
    }

    task "prometheus" {
      artifact {
        source      = "https://github.com/prometheus/prometheus/releases/download/v${var.prom_version}/prometheus-${var.prom_version}.linux-amd64.tar.gz"
        destination = "local"

        // options {
        //   checksum = "sha256:${var.prom_sha2}"
        // }
      }
      template {
        change_mode   = "signal"
        change_signal = "SIGHUP"
        destination   = "local/prometheus.yml"
        data          = file("templates/prometheus.yml.tpl")
        wait {
          min = "10s"
          max = "20s"
        }
      }

      template {
        change_mode     = "noop"
        destination     = "local/node-rules.yml"
        left_delimiter  = "[["
        right_delimiter = "]]"
        wait {
          min = "10s"
          max = "20s"
        }
        data = file("templates/node-rules.yml.tpl")
      }
      driver = "exec"

      config {
        command = "local/prometheus-${var.prom_version}.linux-amd64/prometheus"
        args = [
          "--config.file=local/prometheus.yml",
          "--storage.tsdb.retention.size=1GB",
          "--storage.tsdb.retention.time=7d",
          "--web.listen-address=:${NOMAD_PORT_prometheus_ui}",
          "--web.enable-admin-api",
          "--storage.tsdb.path=data"
        ]
      }

      resources {
        cpu    = 1000
        memory = 1024
      }

      service {
        name = "prometheus"
        tags = ["urlprefix-/prometheus"]
        port = "prometheus_ui"

        check {
          name     = "prometheus_readiness check"
          type     = "http"
          path     = "/-/ready"
          interval = "10s"
          timeout  = "2s"
        }
        check {
          name     = "prometheus healthiness check"
          type     = "http"
          path     = "/-/healthy"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }

  group "mimir" {
    count = 1

    network {
      port "mimir_ui" {}
    }

    restart {
      attempts = 1
      interval = "7m"
      delay    = "1m"
      mode     = "delay"
    }

    reschedule {
      delay          = "5m"
      delay_function = "fibonacci"
      unlimited      = true
    }

    update {
      max_parallel      = 1
      min_healthy_time  = "20s"
      healthy_deadline  = "5m"
      progress_deadline = "15m"
      auto_revert       = true
      auto_promote      = true
      canary            = 1
    }

    migrate {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "30s"
      healthy_deadline = "10m"
    }

    ephemeral_disk {
      size = 300
    }

    task "mimir" {
      vault {
        // policies      = ["read-only"]
        change_mode   = "restart"
        change_signal = "SIGHUP"
      }
      artifact {
        source      = "https://github.com/grafana/mimir/releases/download/mimir-${var.mimir_version}/mimir-linux-amd64"
        destination = "local"

        // options {
        //   checksum = "sha256:${var.mimir_sha2}"
        // }
      }
      template {
        change_mode   = "signal"
        change_signal = "SIGHUP"
        destination   = "local/mimir.yml"
        data          = file("templates/mimir.yml.tpl")
        wait {
          min = "10s"
          max = "20s"
        }
      }

      driver = "exec"

      config {
        command = "local/mimir-linux"
        args = [
          "-server.http-listen-port=${NOMAD_PORT_mimir_ui}",
          "--config.file=local/mimir.yml"
        ]
      }

      resources {
        cpu    = 250
        memory = 400
      }

      service {
        name = "mimir"
        tags = ["urlprefix-/mimir strip=/mimir"]
        port = "mimir_ui"

        provider = "consul"

        check {
          name     = "mimir_readiness check"
          type     = "http"
          path     = "/ready"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }

  group "db" {
    count = 1
    network {
      port "mysql_server" {
        static = 3306
        to     = 3306
      }
      mode = "host"
    }

    constraint {
      attribute = "${attr.cpu.arch}"
      operator  = "="
      value     = "amd64"
    }
    service {
      name = "mysql"
      tags = ["db", "urlprefix-/mysql:3306 proto=tcp"]
      port = "mysql_server"

      check {
        type     = "tcp"
        name     = "mysql_alive"
        interval = "5s"
        timeout  = "2s"
        port     = "mysql_server"
      }
    }

    restart {
      attempts = 1
      interval = "10m"
      delay    = "15s"
      mode     = "fail"
    }

    update {
      max_parallel      = 1
      min_healthy_time  = "20s"
      healthy_deadline  = "5m"
      progress_deadline = "15m"
      auto_revert       = true
      auto_promote      = true
      canary            = 1
    }

    migrate {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "30s"
      healthy_deadline = "10m"
    }

    task "mysql" {
      driver = "docker"
      config {
        image        = "mysql:oracle"
        ports        = ["mysql_server"]
        network_mode = "host"
      }
      env {
        MYSQL_ROOT_PASSWORD = "password" # pragma: allowlist secret
        MYSQL_USER          = "mysql"
        MYSQL_PASSWORD      = "password" # pragma: allowlist secret
        MYSQL_DATABASE      = "grafana"
      }
      resources {
        cpu    = 500
        memory = 512
      }
    }
  }

  group "grafana" {
    count = 1
    network {
      port "grafana_server" {}
    }

    affinity {
      attribute = "${memory.totalbytes}"
      weight    = 50
      operator  = ">="
      value     = "307863731"
    }

    affinity {
      attribute = "${cpu.frequency}"
      weight    = 100
      operator  = ">="
      value     = "2000"
    }

    // volume "grafana_data" {
    //   type = "csi"
    //   source = "grafana"
    //   read_only = false
    //   attachment_mode = "file-system"
    //   access_mode = "single-node-writer"
    // }

    service {
      name = "grafana"
      tags = ["urlprefix-/grafana strip=/grafana"]
      port = "grafana_server"

      check {
        port     = "grafana_server"
        name     = "grafana-api"
        path     = "/api/health"
        type     = "http"
        interval = "1m"
        timeout  = "10s"
      }
    }

    restart {
      attempts = 1
      interval = "2m"
      delay    = "15s"
      mode     = "fail"
    }

    # Select ARMv7 machines
    constraint {
      attribute = "${attr.cpu.arch}"
      operator  = "="
      value     = "amd64"
    }

    update {
      max_parallel      = 1
      min_healthy_time  = "20s"
      healthy_deadline  = "10m"
      progress_deadline = "15m"
      auto_revert       = true
      auto_promote      = true
      canary            = 1
    }

    migrate {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "15s"
      healthy_deadline = "10m"
    }

    // ephemeral_disk {
    //   size = 200
    // }

    vault {
      // policies      = ["read-only"]
      change_mode   = "restart"
      change_signal = "SIGHUP"
    }

    task "wait-for-db" {
      lifecycle {
        hook = "prestart"
      }
      driver = "raw_exec"
      config {
        command = "sh"
        args    = ["-c", "while ! nc -z mysql.service.consul 3306 ; do sleep 1 ; done"]
      }
      // volume_mount {
      // volume = "grafana_data"
      // destination = "${NOMAD_ALLOC_DIR}/data"
      // }
    }

    task "grafana" {
      driver = "docker"
      logs {
        max_files     = 1
        max_file_size = 15
      }

      resources {
        cores  = 1
        memory = 2048
      }

      env {
        GF_PATHS_CONFIG = "/local/conf.ini"
        GF_PATHS_HOME   = "/home/grafana"
      }
      config {
        image        = "grafana/grafana:${var.grafana_version}"
        ports        = ["grafana_server"]
        network_mode = "bridge"
      }

      template {
        data        = file("templates/grafana.ini.tpl")
        destination = "local/conf.ini"
        perms       = "0666"
        uid         = "472"
      } // Configuration template
    }   // Grafana server task
  }     // grafana server group
}
