job "keycloak" {
  datacenters = ["dc1"]
  type        = "service"
  vault {}

  group "keycloak" {
    network {
      port "ui" {
        static = 8080
      }
      port "mgmt" {
        to = 9000
      }
    }

    task "keycloak" {
      consul {}
      service {
        name = "platform-keycloak"
        port = "mgmt"
        check {
          name     = "keycloak-started"
          type     = "http"
          path     = "/health/started"
          interval = "30s"
          timeout  = "2s"
        }
        check {
          name     = "keycloak-liveness"
          type     = "http"
          path     = "/health/live"
          interval = "30s"
          timeout  = "2s"
        }
        check {
          name     = "keycloak-readiness"
          type     = "http"
          path     = "/health/ready"
          interval = "30s"
          timeout  = "2s"
        }
      }
      template {
        data        = <<EOF
{{ range service "master.default" }}
KC_DB_URL="jdbc:postgresql://{{ .Address }}:{{ .Port }}/keycloak"
{{ end }}
{{ with secret "hashiatho.me-v2/data/keycloak" }}
KC_DB_PASSWORD="{{ .Data.data.db_password }}"
KC_DB_USERNAME="{{ .Data.data.db_username }}"
KC_BOOTSTRAP_ADMIN_USERNAME="{{ .Data.data.admin_username }}"
KC_BOOTSTRAP_ADMIN_PASSWORD="{{ .Data.data.admin_password }}"
{{ end }}
EOF
        destination = "secrets/keycloak.env"
        env         = true
      }
      resources {
        memory = 2048
        cpu    = 2000
      }
      driver = "docker"
      env {
        KC_DB                             = "postgres"
        KC_DB_USERNAME                    = "keycloak"
        KC_DB_SCHEMA                      = "keycloak"
        KC_HEALTH_ENABLED                 = true
        KC_METRICS_ENABLED                = true
        KC_HTTP_ENABLED                   = true
        KC_HOSTNAME_STRICT                = false
        KC_HTTP_MANAGEMENT_HEALTH_ENABLED = true
        KC_HTTP_MANAGEMENT_SCHEME         = "http"
      }

      template {
        destination = "local/start.sh"
        change_mode = "restart"
        perms       = "0777"
        data        = <<EOT
#!/bin/bash
echo ${KC_BOOTSTRAP_ADMIN_USERNAME}
env
/opt/keycloak/bin/kc.sh build
/opt/keycloak/bin/kc.sh bootstrap-admin user --username admain --password:env KC_BOOTSTRAP_ADMIN_PASSWORD
/opt/keycloak/bin/kc.sh start --optimized
        EOT
      }
      config {
        image      = "quay.io/keycloak/keycloak:26.7.2"
        entrypoint = ["local/start.sh"]
        ports      = ["ui", "mgmt"]
      }
    }
  }
}
