variable "consul_esm_version" {
  type    = string
  default = "0.7.1"
}

job "consul-esm" {
  group "main" {
    network {
      port "metrics" {
        to = "9000"
      }
    }
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
      env {
        log_level = "INFO"
      }
      // scaling {
      //   enabled = true
      //   min = 0
      //   max = 3
      //   policy {

      //   }
      // }
      service {
        port = "metrics"
        check {
          name     = "metrics_health"
          type     = "http"
          path     = "/metrics"
          interval = "1m"
          timeout  = "5s"
        }
      }
      driver = "exec"
      config {
        command = "local/consul-esm"
        args = [
          "-config-dir=local"
        ]
      }

      template {
        data        = <<EOT
log_level = "{{ env "log_level" }}"
enable_syslog = false
log_json = false
instance_id = "${uuidv4()}"
consul_service = "consul-esm"
consul_service_tag = ""
consul_kv_path = "consul-esm/"
external_node_meta {
    "external-node" = "true"
}
node_reconnect_timeout = "72h"
node_reconnect_timeout = "72h"
node_probe_interval = "10s"
disable_coordinate_updates = false
http_addr = "localhost:8500"
token = ""
datacenter = "dc1"
client_address = "{{ env "NOMAD_ADDR_metrics" }}"
ping_type = "udp"
telemetry {
	disable_hostname = false
 	filter_default = false
 	prefix_filter = []
 	metrics_prefix = "/v1/esm/metrics"
 	prometheus_retention_time = "30s"
}
passing_threshold = 0
critical_threshold = 0
        EOT
        destination = "local/config.hcl"
        perms       = "0644"

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
