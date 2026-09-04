variable "platform_postgres_service" {
  type    = string
  default = "platform-data-plane-default"
}

job "keycloak" {
  constraint {
    attribute = "${meta.model}"
    operator  = "="
    value     = "Raspberry Pi 5 Model B Rev 1.1"
  }
  datacenters = ["dc1"]
  type        = "service"
  vault {}

  group "keycloak" {

    network {
      dns {
        servers = ["172.17.0.1"]
      }
      # mode = "bridge"
      port "ui" {
        static = 8080
      }
      port "mgmt" {
        to = 9000
      }
    } // group network

    task "db-init" {
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }
      consul {}
      driver = "docker"
      config {
        image   = "postgres:17.9-alpine"
        command = "psql"
        args = [
          "-h", "${DB_ADDR}",
          "-U", "${DB_USER}",
          "-p", "${DB_PORT}",
          "-f", "local/init-user.sql",
          "-f", "local/init-db.sql"
        ]
        # dns_servers = ["127.0.0.1", "${attr.unique.network.ip-address}", "1.1.1.1"]
      } // prestart task config

      template {
        destination = "local/init-user.sql"
        data        = <<EOT
      {{ with secret "hashiatho.me-v2/data_plane" }}
      -- Create keycloak user if it doesn't exist
      DO $$
      BEGIN
        CREATE USER {{ .Data.data.db_username }} WITH PASSWORD '{{ .Data.data.db_password }}';
      EXCEPTION WHEN DUPLICATE_OBJECT THEN
        NULL;
      END
      $$;
      {{ end }}
      EOT
        perms       = "0644"
      }

      template {
        destination = "local/init-db.sql"
        data        = <<EOT
{{ with secret "hashiatho.me-v2/keycloak" }}
-- Create keycloak database if it doesn't exist
CREATE DATABASE keycloak OWNER keycloak;

-- Connect to keycloak database
\c keycloak

-- Create schema if it doesn't exist
CREATE SCHEMA IF NOT EXISTS keycloak;

-- Grant permissions on database
GRANT CONNECT ON DATABASE keycloak TO keycloak;

-- Grant permissions on schemas
GRANT USAGE ON SCHEMA public TO keycloak;
GRANT USAGE ON SCHEMA keycloak TO keycloak;
GRANT CREATE ON SCHEMA public TO keycloak;
GRANT CREATE ON SCHEMA keycloak TO keycloak;

-- Grant permissions on existing tables
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO keycloak;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA keycloak TO keycloak;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO keycloak;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA keycloak TO keycloak;

-- Set default privileges for future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO keycloak;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO keycloak;
ALTER DEFAULT PRIVILEGES IN SCHEMA keycloak GRANT ALL ON TABLES TO keycloak;
ALTER DEFAULT PRIVILEGES IN SCHEMA keycloak GRANT ALL ON SEQUENCES TO keycloak;
{{ end }}
EOT
        perms       = "0644"
      } // db init template

      template {
        data        = <<EOH
{{ range service "primary.platform-data-plane-default" }}
DB_ADDR="{{ .Address }}"
DB_PORT="{{ .Port }}"
{{ end }}
{{ with secret "hashiatho.me-v2/data_plane" }}
DB_PASSWORD="{{ .Data.data.postgres_root_password }}"
PGPASSWORD="{{ .Data.data.postgres_root_password }}"
DB_USER="{{ .Data.data.postgres_root_user }}"
{{ end }}
          EOH
        destination = "secrets/db.env"
        env         = true
        # wait {
        #     min = "2s"
        #     max = "10s"
        # }
      } // secrets template
    }   // task

    task "migration" {
      consul {}
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }
      driver = "docker"
      template {
        destination = "local/rclone.conf"
        perms       = "0644"
        data        = <<EOT
{{ with secret "hashiatho.me-v2/cloudflare" }}
[r2]
type = s3
provider = Cloudflare
access_key_id = {{ .Data.data.platform_state_bucket_access_key_id }}
secret_access_key = {{ .Data.data.platform_state_bucket_secret_access_key }}
endpoint = {{ .Data.data.platform_access_bucket_endpoint }}
acl = private
{{ end }}
        EOT
      }
      // Remote bucket credentials
      template {
        data        = <<EOH
  {{ with secret "hashiatho.me-v2/cloudflare" }}
  AWS_ACCESS_KEY_ID = "{{ .Data.data.platform_state_bucket_access_key_id }}"
  AWS_SECRET_ACCESS_KEY = "{{ .Data.data.platform_state_bucket_secret_access_key }}"
  BUCKET_NAME = "{{ .Data.data.platform_state_bucket }}"
  {{ end }}
  EOH
        destination = "secrets/r2.env"
        env         = true
      }
      config {
        image = "rclone/rclone:latest"
        args  = ["--config", "/local/rclone.conf", "tree", "r2:${BUCKET_NAME}"]
      }
    }

    task "keycloak" {
      consul {}
      service {
        name = "platform-keycloak"
        port = "mgmt"
        tags = [""]
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
{{ range service "primary.${var.platform_postgres_service}" }}
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
/opt/keycloak/bin/kc.sh bootstrap-admin user --username admin --password:env KC_BOOTSTRAP_ADMIN_PASSWORD
# Create adamin user
# Create client for Terraform
{{ with secret "hashiatho.me-v2/keycloak" }}
# $ kcadm.sh create clients -r master -s clientId=terraform -s enabled=true -s clientAuthenticatorType=client-secret -s secret={{ .Data.data.terraform_client_id }}
{{ end }}
/opt/keycloak/bin/kc.sh start --optimized
        EOT
      }
      config {
        image      = "quay.io/keycloak/keycloak:26.7.2"
        entrypoint = ["local/start.sh"]
        ports      = ["ui", "mgmt"]
      }
    } // task
  }   // group
}     // job
