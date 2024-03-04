job "keycloak" {

  datacenters = ["dc1"]
  type        = "service"

  group "keycloak" {
    network {
      mode = "host"
      port "http" {
        to = 8080
      }
      port "https" {
        to = 8443
      }
    }

    update {
      max_parallel      = 2
      health_check      = "checks"
      min_healthy_time  = "10s"
      healthy_deadline  = "5m"
      progress_deadline = "10m"
      auto_revert       = true
      auto_promote      = true
      canary            = 1
      stagger           = "30s"
    }

    task "keycloak" {
      driver = "docker"
      vault {
        change_mode = "signal"
        role        = "nomad-workloads"
      }
      template {
        data        = <<EOH
      {{- with secret "hashiatho.me-v2/data/keycloak" -}}
      KEYCLOAK_ADMIN={{ .Data.data.admin_username }}
      KEYCLOAK_ADMIN_PASSWORD={{ .Data.data.admin_password }}
      {{ end }}
      EOH
        destination = "secrets/.env"
        env         = true
      }
      template {
        data        = <<EOH
      {{ with pkiCert "pki_hah_int/issue/hah_int_role" "common_name=keycloak.service.consul" }}
      {{- .Cert -}}
      {{ end }}
        EOH
        destination = "${NOMAD_TASK_DIR}/keycloak-cert.pem"
        change_mode = "restart"
        perms       = "644"
        uid         = "1000"
      }

      template {
        data        = <<EOH
      {{ with pkiCert "pki_hah_int/issue/hah_int_role" "common_name=keycloak.service.consul" }}
      {{- .CA -}}
      {{ end }}
        EOH
        destination = "${NOMAD_TASK_DIR}/keycloak-ca.pem"
        change_mode = "restart"
        uid         = "1000"
      }

      template {
        data        = <<EOH
      {{ with pkiCert "pki_hah_int/issue/hah_int_role" "common_name=keycloak.service.consul" }}
      {{- .Key -}}
      {{ end }}
        EOH
        destination = "${NOMAD_TASK_DIR}/keycloak-key.pem"
        change_mode = "restart"
        perms       = "400"
        uid         = "1000"
      }

      env {
        KC_HEALTH_ENABLED              = "true"
        KC_METRICS_ENABLED             = "true"
        KC_HOSTNAME                    = "${NOMAD_IP_http}"
        KC_LOG_CONSOLE_COLOR           = "true"
        KC_HTTP_ENABLED                = "true"
        KC_HOSTNAME_STRICT             = "false"
        KC_HOSTNAME_STRICT_BACKCHANNEL = "false"
        KC_HTTPS_CERTIFICATE_FILE      = "${NOMAD_TASK_DIR}/keycloak-cert.pem"
        KC_HTTPS_CERTIFICATE_KEY_FILE  = "${NOMAD_TASK_DIR}/keycloak-key.pem"
        KC_HOSTNAME_ADMIN_URL          = "http://${NOMAD_ADDR_http}"
      }

      config {
        image = "quay.io/keycloak/keycloak:latest"
        ports = ["http", "https"]
        args  = ["start"]
      }
      resources {
        cores  = 2
        memory = "1000"
      }

      constraint {
        attribute = "${attr.unique.storage.bytesfree}"
        operator  = ">"
        value     = 81673420
      }

      service {
        provider = "consul"
        name     = "keycloak-server-http"
        port     = "http"
        tags     = ["keycloak"]

        check {
          name     = "keycloak-alive"
          type     = "http"
          port     = "http"
          protocol = "http"
          path     = "/health/live"
          interval = "10s"
          timeout  = "5s"
        }

        check {
          name     = "keycloak-ready"
          type     = "http"
          port     = "http"
          protocol = "http"
          path     = "/health/ready"
          interval = "30s"
          timeout  = "5s"
        }
        address_mode = "driver"
      }
    }
  }
}
