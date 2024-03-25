variable "consul_esm_version" {
  type    = string
  default = "0.7.1"
}

job "consul-esm" {
  group "main" {

    count = 1

    update {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "20s"
      healthy_deadline = "5m"
      auto_revert      = true
      auto_promote     = true
      canary           = 1
    }

    migrate {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "10s"
      healthy_deadline = "5m"
    }

    task "monitor" {

      // scaling {
      //   enabled = true
      //   min = 0
      //   max = 3
      //   policy {

      //   }
      // }

      driver = "exec"
      config {
        command = "local/consul-esm"
      }
      artifact {
        source      = "https://releases.hashicorp.com/consul-esm/${var.consul_esm_version}/consul-esm_${var.consul_esm_version}_linux_arm64.zip"
        destination = "local/consul-esm"
        mode        = "file"
      }
      identity {
        env  = true
        file = true
      }

      resources {
        cpu    = 50
        memory = 25
      }
    }
  }
}
