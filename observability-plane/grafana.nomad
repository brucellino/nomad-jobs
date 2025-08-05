variable "grafana_version" {
  type        = string
  default     = "9.4.7"
  description = "Grafana version"
}

// variable "grafana_admin_password" {
//   type = string
//   // sensitive = true
//   description = "Password for the grafana admin interface"
// }

// locals {
//   grafana_arm = "https://dl.grafana.com/oss/release/grafana-${var.grafana_version}.linux-armv6.tar.gz"
//   grafana_64 = "https://dl.grafana.com/oss/release/grafana-${var.grafana_version}.linux-arm64.tar.gz"
//   grafana_url = "${attr.cpu.arch == "arm64" ? local.grafana_64 : local.grafana_arm}"
// }

job "dashboard" {

  datacenters = ["dc1"]
  type        = "service"

  # Select ARMv7 machines
  constraint {
    attribute = "${attr.cpu.arch}"
    operator  = "="
    value     = "arm64"
  }

  update {
    max_parallel      = 1
    min_healthy_time  = "20s"
    healthy_deadline  = "5m"
    progress_deadline = "10m"
    auto_revert       = true
    auto_promote      = true
    canary            = 1
  }

  migrate {
    max_parallel     = 1
    health_check     = "checks"
    min_healthy_time = "15s"
    healthy_deadline = "5m"
  }

  group "db" {
    count = 1
    network {
      port "mysql_server" {
        static = 3306
        to     = 3306
      }
    }
    service {
      name = "mysql"
      tags = ["db", "dashboard", "urlprefix-/mysql:3306 proto=tcp"]
      port = "mysql_server"

      // check {
      //   type = "tcp"
      //   port = "mysql_server"
      //   name = "mysql_alive"
      //   interval = "30s"
      //   timeout = "5s"
      // }
    }

    restart {
      attempts = 1
      interval = "2m"
      delay    = "15s"
      mode     = "fail"
    }
    task "mysql" {
      leader = true
      driver = "podman"
      config {
        image = "docker://arm64v8/mysql:oracle"
        ports = ["mysql_server"]
      }
      env {
        MYSQL_ROOT_PASSWORD = "password" # pragma: allowlist secret
        MYSQL_USER          = "mysql"
        MYSQL_PASSWORD      = "password" # pragma: allowlist secret
        MYSQL_DATABASE      = "grafana"
      }
      resources {
        cpu    = 1000
        memory = 512
      }
    }
  }


  group "grafana" {
    network {
      port "grafana_server" {}
    }
    # select machines with more than 4GB of RAM
    constraint {
      attribute = "${attr.memory.totalbytes}"
      value     = "500MB"
      operator  = ">="
    }
    service {
      name = "grafana"
      tags = ["monitoring", "dashboard", "urlprefix-/grafana:3000"]
      port = "grafana_server"

      check {
        port     = "grafana_server"
        name     = "grafana-api"
        path     = "/api/health"
        type     = "http"
        interval = "10m"
        timeout  = "10s"
      }
    }

    restart {
      attempts = 1
      interval = "2m"
      delay    = "15s"
      mode     = "fail"
    }

    ephemeral_disk {
      size = 200
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
    }

    task "grafana" {
      driver = "podman"
      logs {
        max_files     = 2
        max_file_size = 15
      }
      resources {
        cpu    = 1000
        memory = 1024
      }

      config {
        image = "docker://grafana/grafana:${var.grafana_version}"
        args = [
          "-homepath=${NOMAD_ALLOC_DIR}/grafana-${var.grafana_version}",
          "--config=${NOMAD_ALLOC_DIR}/grafana-${var.grafana_version}/conf/conf.ini"
        ]
        ports = ["grafana_server"]
      }

      template {
        data        = file("templates/grafana.ini.tpl")
        destination = "${NOMAD_ALLOC_DIR}/grafana-${var.grafana_version}/conf/conf.ini"
      } // Configuration template
    }   // Grafana server task
  }     // grafana server group
}
