variable "prom_version" {
  default = "2.43.0"
  type = string
  description = "Version of prometheus to use"
}

variable "prom_sha2" {
  type = string
  default = "79c4262a27495e5dff45a2ce85495be2394d3eecd51f0366c706f6c9c729f672" #pragma: allowlist secret
  description = "https://prometheus.io/download/"
}

variable "mimir_version" {
  default = "2.8.0"
  type = string
  description = "Version of mimir to use"
}

variable "mimir_sha2" {
  type = string
  default = "e7d2d401f616b185bded25cfe84f7b6543e169f4d0d8a36e19f7ba124848b712" #pragma: allowlist secret
  description = "https://prometheus.io/download/"
}

variable "grafana_version" {
  type = string
  default = "9.4.7"
  description = "Grafana version"
}

job "monitoring" {
  datacenters = ["dc1"]
  type        = "service"
  meta {
    auto-backup = true
    backup-schedule = "@daily"
    backup-target-db = "postgres"
  }
  update {
    max_parallel = 2
    health_check = "checks"
    canary = 1
    auto_promote = true
    auto_revert = true
  }

  migrate {
    max_parallel = 1
    health_check = "checks"
    min_healthy_time = "30s"
    healthy_deadline = "10m"
  }
  constraint {
     attribute = attr.cpu.arch
     value     = "arm64"
  }

  group "prometheus" {
    count = 1
    volume "data" {
      type      = "host"
      read_only = false
      source    = "scratch"
    }
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
      delay = "5m"
      delay_function = "fibonacci"
      unlimited = true
    }

    ephemeral_disk {
      size = 300
    }

    task "prometheus" {
      artifact {
        source      = "https://github.com/prometheus/prometheus/releases/download/v${var.prom_version}/prometheus-${var.prom_version}.linux-arm64.tar.gz"
        destination = "local"

        options {
          checksum = "sha256:${var.prom_sha2}"
        }
      }
      template {
        change_mode = "signal"
        change_signal = "SIGHUP"
        destination = "local/prometheus.yml"
        data = file("templates/prometheus.yml.tpl")
        wait {
          min = "10s"
          max = "20s"
        }
      }

      template {
        change_mode = "noop"
        destination = "local/node-rules.yml"
        left_delimiter = "[["
        right_delimiter = "]]"
        wait {
          min = "10s"
          max = "20s"
        }
        data = file("templates/node-rules.yml.tpl")
      }
      driver = "exec"

      config {
        command = "local/prometheus-${var.prom_version}.linux-arm64/prometheus"
        args    = [
          "--config.file=local/prometheus.yml",
          "--storage.tsdb.retention.size=1GB",
          "--storage.tsdb.retention.time=7d",
          "--web.listen-address=:${NOMAD_PORT_prometheus_ui}",
          "--web.enable-admin-api",
          "--storage.tsdb.path=data"
        ]
      }
      volume_mount {
        volume      = "data"
        destination = "data"
        read_only   = false
      }
      resources {
        cpu = 250
        memory = 400
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
    volume "data" {
      type      = "host"
      read_only = false
      source    = "scratch"
    }
    network {
      port "mimir_ui" {}
    }

    restart {
      attempts = 1
      interval = "7m"
      delay    = "1m"
      mode     = "fail"
    }

    reschedule {
      delay = "5m"
      delay_function = "fibonacci"
      unlimited = true
    }

    ephemeral_disk {
      size = 300
    }

    task "mimir" {
      vault {
        policies = ["read-only"]
        change_mode = "restart"
        change_signal = "SIGHUP"
      }
      artifact {
        source      = "https://github.com/grafana/mimir/releases/download/mimir-${var.mimir_version}/mimir-linux-arm64"
        destination = "local"
        options {
          checksum = "sha256:${var.mimir_sha2}"
        }
      }
      template {
        change_mode = "signal"
        change_signal = "SIGHUP"
        destination = "local/mimir.yml"
        data = file("templates/mimir.yml.tpl")
        wait {
          min = "10s"
          max = "20s"
        }
      }

      driver = "exec"

      config {
        command = "local/mimir-linux-arm64"
        args    = [
          "-server.http-listen-port=${NOMAD_PORT_mimir_ui}",
          "--config.file=local/mimir.yml"
        ]
      }
      volume_mount {
        volume      = "data"
        destination = "data"
        read_only   = false
      }
      resources {
        cpu = 250
        memory = 400
      }

      service {
        name = "mimir"
        tags = ["urlprefix-/mimir strip=/mimir"]
        port = "mimir_ui"

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
        to = 3306
      }
      mode = "host"
    }

    constraint {
      attribute = "${attr.cpu.arch}"
      operator  = "="
      value     = "arm64"
    }
    service {
      name = "mysql"
      tags = ["db", "urlprefix-/mysql:3306 proto=tcp"]
      port = "mysql_server"

      // check {
      //   type = "script"
      //   command = "/bin/bash"
      //   args = ["-c", "mysqld status"]
      //   name = "mysql_ready"
      //   interval = "5s"
      //   timeout = "2s"
      //   task = "mysql"
      // }

      check {
        type = "tcp"
        name = "mysql_alive"
        interval = "5s"
        timeout = "2s"
        port = "mysql_server"
      }
    }

    restart {
      attempts = 1
      interval = "10m"
      delay = "15s"
      mode = "fail"
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
      max_parallel = 1
      health_check = "checks"
      min_healthy_time = "30s"
      healthy_deadline = "10m"
    }

    task "mysql" {
      driver = "podman"
      config {
        image = "docker://arm64v8/mysql:oracle"
        ports = ["mysql_server"]
        network_mode = "host"
      }
      env {
        MYSQL_ROOT_PASSWORD = "password" # pragma: allowlist secret
        MYSQL_USER = "mysql"
        MYSQL_PASSWORD = "password" # pragma: allowlist secret
        MYSQL_DATABASE = "grafana"
      }
      resources {
        cpu    = 125
        memory = 1000
      }
    }
  }

  group "grafana" {
    count = 1
    network {
      port "grafana_server" {}
    }

    service {
      name = "grafana"
      tags = ["urlprefix-/grafana strip=/grafana"]
      port = "grafana_server"

      check {
        port = "grafana_server"
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
      delay = "15s"
      mode = "fail"
    }

    # Select ARMv7 machines
    constraint {
      attribute = "${attr.cpu.arch}"
      operator  = "="
      value     = "arm64"
    }

    # select machines with more than 4GB of RAM
    // constraint {
    //   attribute = "${attr.memory.totalbytes}"
    //   value     = "500MB"
    //   operator  = ">="
    // }
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
      max_parallel = 1
      health_check = "checks"
      min_healthy_time = "15s"
      healthy_deadline = "10m"
    }

    ephemeral_disk {
      size = 200
    }

    vault {
      policies = ["read-only"]
      change_mode = "restart"
      change_signal = "SIGHUP"
    }

    task "wait-for-db" {
      lifecycle {
        hook = "prestart"
      }
      driver = "exec"
      config {
        command = "sh"
        args = ["-c", "while ! nc -z mysql.service.consul 3306 ; do sleep 1 ; done"]
      }
    }

    task "grafana" {
      driver = "exec"
      logs {
        max_files     = 10
        max_file_size = 15
      }
      artifact {
        // source = local.grafana_url
        source = "https://dl.grafana.com/oss/release/grafana-${var.grafana_version}.linux-arm64.tar.gz"
        destination = "${NOMAD_ALLOC_DIR}"
      }
      resources {
        cpu    = 1000
        memory = 512
      }

      config {
        command = "${NOMAD_ALLOC_DIR}/grafana-${var.grafana_version}/bin/grafana-server"
        args = [
          "-homepath=${NOMAD_ALLOC_DIR}/grafana-${var.grafana_version}",
          "--config=${NOMAD_ALLOC_DIR}/grafana-${var.grafana_version}/conf/conf.ini"
        ]
      }

      template {
        data = file("templates/grafana.ini.tpl")

        destination = "${NOMAD_ALLOC_DIR}/grafana-${var.grafana_version}/conf/conf.ini"
      } // Configuration template
    } // Grafana server task
  } // grafana server group
}
