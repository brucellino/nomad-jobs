variable "grafana_version" {
  type = string
  default = "8.5.0"
  description = "Grafana version"
}

// locals {
//   grafana_arm = "https://dl.grafana.com/oss/release/grafana-${var.grafana_version}.linux-armv6.tar.gz"
//   grafana_64 = "https://dl.grafana.com/oss/release/grafana-${var.grafana_version}.linux-arm64.tar.gz"
//   grafana_url = "${attr.cpu.arch == "arm64" ? local.grafana_64 : local.grafana_arm}"
// }

job "dashboard" {

  datacenters = ["dc1"]
  type = "service"

  # Select ARMv7 machines
  constraint {
    attribute = "${attr.cpu.arch}"
    operator  = "="
    value     = "arm64"
  }

  # select machines with more than 4GB of RAM
  constraint {
    attribute = "${attr.memory.totalbytes}"
    value     = "1GB"
    operator  = ">="
  }
  update {
    max_parallel      = 1
    min_healthy_time  = "20s"
    healthy_deadline  = "20m"
    progress_deadline = "30m"
    auto_revert       = true
    auto_promote      = true
    canary            = 1
  }

  migrate {
    max_parallel = 1
    health_check = "checks"
    min_healthy_time = "15s"
    healthy_deadline = "5m"
  }

  group "db" {
    count = 1
    network {
      port "mysql_server" {
        static = 3306
        to = 3306
      }
    }
    service {
      name = "mysql"
      tags = ["db", "dashboard"]
      port = "mysql_server"

      check {
        type = "tcp"
        port = "mysql_server"
        name = "mysql_alive"
        interval = "20s"
        timeout = "2s"
      }
    }

    restart {
      attempts = 1
      interval = "2m"
      delay = "15s"
      mode = "fail"
    }
    task "mysql" {
      leader = true
      driver = "docker"
      config {
        image = "arm64v8/mysql:oracle"
        ports = ["mysql_server"]
      }
      env {
        MYSQL_ROOT_PASSWORD = "password" # pragma: allowlist secret
        MYSQL_USER = "mysql"
        MYSQL_PASSWORD = "password" # pragma: allowlist secret
        MYSQL_DATABASE = "grafana"
      }
      resources {
        cpu    = 125
        memory = 512
      }
    }
  }


  group "grafana" {
    count = 1
    network {
      port "grafana_server" {
        to = 3000
        static = 3000
      }
    }

    service {
      name = "grafana"
      tags = ["monitoring", "dashboard"]
      port = "grafana_server"

      check {
        port = "grafana_server"
        name     = "grafana-api"
        path     = "/api/health"
        type     = "http"
        interval = "20s"
        timeout  = "5s"
      }
    }

    restart {
      attempts = 1
      interval = "2m"
      delay = "15s"
      mode = "fail"
    }

    ephemeral_disk {
      size = 300
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
        memory = 1024
      }

      config {
        command = "${NOMAD_ALLOC_DIR}/grafana-${var.grafana_version}/bin/grafana-server"
        args = [
          "-homepath=${NOMAD_ALLOC_DIR}/grafana-${var.grafana_version}",
          "--config=${NOMAD_ALLOC_DIR}/grafana-${var.grafana_version}/conf/conf.ini"
        ]
      }

      template {
        data = <<EOT
[auth.anonymous]
enabled = true
[server]
protocol = http
http_port = ${NOMAD_HOST_PORT_grafana_server}
# cert_file = none
# cert_key = none
[database]
type = mysql
host = mysql.service.consul:3306
user = root
password = """password"""
ssl_mode = disable
# ca_cert_path = none
# client_key_path = none
# client_cert_path = none
# server_cert_name = none

[paths]
data = ${NOMAD_ALLOC_DIR}/data/
logs = ${NOMAD_ALLOC_DIR}/log/
plugins = ${NOMAD_ALLOC_DIR}/plugins
[analytics]
reporting_enabled = false
[snapshots]
external_enabled = false
[security]
admin_user = admin
admin_password = "admin"
disable_gravatar = true
[dashboards]
versions_to_keep = 10
[alerting]
enabled = true
[unified_alerting]
enabled = false
EOT

        destination = "${NOMAD_ALLOC_DIR}/grafana-${var.grafana_version}/conf/conf.ini"
      } // Configuration template
    } // Grafana server task
  } // grafana server group
}
