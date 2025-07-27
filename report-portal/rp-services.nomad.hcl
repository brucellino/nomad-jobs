variable "db" {
  type = object({
    db_name = string
  })
  default = {
    db_name = "reportportal"
  }
  description = "Database configuration"
}
job "report-portal" {
  reschedule {
    delay          = "30s"
    delay_function = "exponential"
    max_delay      = "1h"
    unlimited      = true
  }

  group "rp-sevices" {
    network {
      port "index" {
        to = 8080
      }
      port "ui" {
        to = 8080
      }
      port "api" {
        to = 8585
      }
      port "uat" {
        to = 9999
      }
      port "job" {
        to = 8686
      }
    }
    volume "storage" {
      type      = "host"
      source    = "scratch"
      read_only = false
    }
    vault {
      policies    = ["nomad-read", "nomad-workloads", "default"]
      change_mode = "noop"
      env         = true
    }

    restart {
      attempts         = 3
      delay            = "30s"
      render_templates = true
      mode             = "delay"
    }

    task "index" {
      service {
        tags = [
          "traefik.http.routers.index.rule=PathPrefix(`/`)",
          "traefik.http.routers.index.service=index",
          "traefik.http.services.index.loadbalancer.server.port=8080",
          "traefik.http.services.index.loadbalancer.server.scheme=http",
          "traefik.expose=true"
        ]
        port     = "index"
        name     = "rp-index"
        provider = "consul"

        check {
          name     = "index"
          type     = "http"
          path     = "/health"
          interval = "10s"
          timeout  = "2s"
        }
      }
      template {
        data        = <<EOF
LB_URL="http://{{- range service "rp-traefik-mgmt" }}{.Name}:{.Port}{{end}}"
TRAEFIK_V2_MODE=true
EOF
        destination = "local/index.env"
        env         = true
      }
      driver = "docker"
      config {
        image = "reportportal/service-index:5.14.0"
        ports = ["index"]
      }
    } // service index task

    task "ui" {
      service {
        tags = [
          "traefik.http.middlewares.ui-strip-prefix.stripprefix.prefixes=/ui",
          "traefik.http.routers.ui.middlewares=ui-strip-prefix@docker",
          "traefik.http.routers.ui.rule=PathPrefix(`/ui`)",
          "traefik.http.routers.ui.service=ui",
          "traefik.http.services.ui.loadbalancer.server.port=8080",
          "traefik.http.services.ui.loadbalancer.server.scheme=http",
          "traefik.expose=true"
        ]
        check {
          name     = "ui"
          port     = "ui"
          type     = "http"
          path     = "/health"
          interval = "10s"
          timeout  = "2s"
        }
      }
      env {
        RP_SERVER_PORT = "${NOMAD_PORT_ui}"
      }
      driver = "docker"
      config {
        image = "reportportal/service-ui:5.14.2"
        ports = ["ui"]
      }
    } // ui task

    task "jobs" {
      lifecycle {
        hook = "poststart"
      }
      resources {
        cpu    = 1024
        memory = 1024

      }
      vault {
        policies      = ["nomad-read"]
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }
      driver = "docker"
      config {
        image = "reportportal/service-jobs:5.14.0"
        ports = ["job"]
      }

      env {
        RP_AMQP_ANALYZER-VHOST = "analyzer"

      }

      template {
        data        = <<EOF
DATASTORE_TYPE="filesytem"
RP_ENVIRONMENT_VARIABLE_CLEAN_ATTACHMENT_CRON="0 0 */24 * * *"
RP_ENVIRONMENT_VARIABLE_CLEAN_LOG_CRON="0 0 */24 * * *"
RP_ENVIRONMENT_VARIABLE_CLEAN_LAUNCH_CRON="0 0 */24 * * *"
RP_ENVIRONMENT_VARIABLE_CLEAN_STORAGE_CRON="0 0 */24 * * *"
RP_ENVIRONMENT_VARIABLE_STORAGE_PROJECT_CRON="0 */5 * * * *"
RP_ENVIRONMENT_VARIABLE_CLEAN_EXPIREDUSER_CRON="0 0 */24 * * *"
RP_ENVIRONMENT_VARIABLE_CLEAN_EXPIREDUSER_RETENTIONPERIOD="365"
RP_ENVIRONMENT_VARIABLE_NOTIFICATION_EXPIREDUSER_CRON="0 0 */24 * * *"
RP_ENVIRONMENT_VARIABLE_CLEAN_EVENTS_RETENTIONPERIOD=365
RP_ENVIRONMENT_VARIABLE_CLEAN_EVENTS_CRON="0 30 05 * * *"
RP_ENVIRONMENT_VARIABLE_CLEAN_STORAGE_CHUNKSIZE=20000
RP_PROCESSING_LOG_MAXBATCHSIZE=2000
RP_PROCESSING_LOG_MAXBATCHTIMEOUT=6000
RP_AMQP_MAXLOGCONSUMER=1
JAVA_OPTS="-Djava.security.egd=file:/dev/./urandom -XX:+UseG1GC -XX:+UseStringDeduplication -XX:G1ReservePercent=20 -XX:InitiatingHeapOccupancyPercent=60 -XX:MaxRAMPercentage=70.0 -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/tmp"
        EOF
        destination = "local/config.env"
        env         = true
      }

      template {
        data        = <<EOF
  {{ with secret "hashiatho.me-v2/data/report_portal" }}
  RP_DB_USER="{{ .Data.data.postgres_user }}"
  RP_DB_PASS="{{ .Data.data.postgres_pass }}"
  RP_AMQP_USER="{{ .Data.data.rabbit_user }}"
  RP_AMQP_PASS="{{ .Data.data.rabbit_pass }}"
  RP_AMQP_APIUSER="{{ .Data.data.rabbit_user }}"
  RP_AMQP_APIPASS="{{ .Data.data.rabbit_pass }}"
  RP_INITIAL_ADMIN_PASSWORD="{{ .Data.data.rp_initial_password }}"
  {{ end }}
  EOF
        destination = "local/creds.env"
        env         = true
      }

      template {
        data        = <<EOF
RP_DB_HOST="{{- range service "report-portal-backing-rp-db" }}{{ .Address }}{{ end }}"
RP_DB_PORT="{{- range service "report-portal-backing-rp-db" }}{{ .Port }}{{ end }}"
RP_AMQP_HOST="{{- range service "rp-rabbit" }}{{ .Address }}{{ end }}"
RP_AMQP_PORT="{{- range service "rp-rabbit" }}{{ .Port }}{{ end }}"
RP_AMQP_APIPORT="{{- range service "rp-rabbit-management" }}{{ .Port }}{{ end }}"
        EOF
        destination = "local/jobs.env"
        env         = true
      } // env template

      service {
        name = "rp-jobs"
        port = "job"
        check {
          type     = "http"
          path     = "/health"
          interval = "30s"
          timeout  = "2s"
        }
        tags = [
          "traefik.http.middlewares.jobs-strip-prefix.stripprefix.prefixes=/jobs",
          "traefik.http.routers.jobs.rule=PathPrefix(`/jobs`)",
          "traefik.http.routers.jobs.service=rp-job",
          "traefik.http.services.jobs.loadbalancer.server.port=${NOMAD_PORT_lb}",
          "traefik.http.services.jobs.loadbalancer.server.scheme=http",
          "traefik.expose=true"
        ]
      }
      volume_mount {
        volume      = "storage"
        destination = "/data/storage"
      }


    } // jobs task

    task "api" {
      driver = "docker"
      vault {
        policies      = ["nomad-read"]
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }

      service {
        port     = "api"
        name     = "rp-api"
        provider = "consul"
        tags = [
          "traefik.http.middlewares.api-strip-prefix.stripprefix.prefixes=/api",
          "traefik.http.routers.api.rule=PathPrefix(`/api`)",
          "traefik.http.routers.api.service=api",
          "traefik.http.services.api.loadbalancer.server.scheme=http",
          "traefik.expose=true"
        ]
        check {
          name     = "rp-api"
          port     = "api"
          type     = "http"
          path     = "/health"
          interval = "80s"
          timeout  = "30s"
        }
      }
      config {
        image = "reportportal/service-api:5.14.0"
        ports = ["api"]
      }

      resources {
        cores  = 2
        memory = 2048
      }
      template {
        data        = <<EOF
{{ range service "report-portal-backing-rp-db" }}
RP_DB_HOST="{{ .Address }}"
RP_DB_PORT="{{ .Port }}"
{{ end }}

{{ with secret "hashiatho.me-v2/data/report_portal" }}
RP_DB_USER="{{ .Data.data.postgres_user }}"
RP_DB_PASS="{{ .Data.data.postgres_pass }}"
RP_AMQP_USER="{{ .Data.data.rabbit_user }}"
RP_AMQP_PASS="{{ .Data.data.rabbit_pass }}"
RP_AMQP_APIUSER="{{ .Data.data.rabbit_user }}"
RP_AMQP_APIPASS="{{ .Data.data.rabbit_pass }}"
{{ end }}

RP_DB_NAME="${var.db.db_name}"
RP_AMQP_HOST="{{- range service "rp-rabbit" }}{{ .Address }}{{ end }}"
RP_AMQP_PORT="{{- range service "rp-rabbit" }}{{ .Port }}{{ end }}"
RP_AMQP_APIPORT="{{- range service "rp-rabbit-management" }}{{ .Port }}{{ end }}"
RP_JOBS_BASEURL="http://{{ env "NOMAD_ADDR_job" }}"
        EOF
        destination = "local/api.env"
        env         = true
      }
      env {
        LOGGING_LEVEL_ORG_HIBERNATE_SQL                          = "info"
        RP_REQUESTLOGGING                                        = false
        AUDIT_LOGGER                                             = "OFF"
        MANAGEMENT_HEALTH_ELASTICSEARCH_ENABLED                  = false
        RP_ENVIRONMENT_VARIABLE_ALLOW_DELETE_ACCOUNT             = false
        JAVA_OPTS                                                = "-Xmx1g -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/tmp -Dcom.sun.management.jmxremote.rmi.port=12349 -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.local.only=false -Dcom.sun.management.jmxremote.port=9010 -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Djava.rmi.server.hostname=0.0.0.0"
        COM_TA_REPORTPORTAL_JOB_INTERRUPT_BROKEN_LAUNCHES_CRON   = "PT1H"
        RP_ENVIRONMENT_VARIABLE_PATTERN-ANALYSIS_BATCH-SIZE      = 100
        RP_ENVIRONMENT_VARIABLE_PATTERN-ANALYSIS_PREFETCH-COUNT  = 1
        RP_ENVIRONMENT_VARIABLE_PATTERN-ANALYSIS_CONSUMERS-COUNT = 1
        COM_TA_REPORTPORTAL_JOB_LOAD_PLUGINS_CRON                = "PT10S"
        COM_TA_REPORTPORTAL_JOB_CLEAN_OUTDATED_PLUGINS_CRON      = "PT10S"
        REPORTING_QUEUES_COUNT                                   = 10
        REPORTING_CONSUMER_PREFETCHCOUNT                         = 10
        REPORTING_PARKINGLOT_TTL_DAYS                            = 7
        DATASTORE_TYPE                                           = "filesystem" # Change to 's3' to use S3 storage
        RP_AMQP_ANALYZER-VHOST                                   = "analyzer"
      }
      volume_mount {
        volume      = "storage"
        destination = "/data/storage"
      }
    } // api task

    task "uat" {
      driver = "docker"
      vault {
        policies      = ["nomad-read"]
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }
      config {
        image = "reportportal/service-authorization:5.14.3"
        ports = ["uat"]
      }
      env {
        RP_SAML_SESSION-LIVE = 4320 ## SAML session duration in minutes (3 days)
      }
      template {
        data        = <<EOF
RP_DB_HOST="{{- range service "report-portal-backing-rp-db" }}{{ .Address }}{{ end }}"
RP_DB_PORT="{{- range service "report-portal-backing-rp-db" }}{{ .Port }}{{ end }}"
{{ with secret "hashiatho.me-v2/data/report_portal" }}
RP_DB_USER="{{ .Data.data.postgres_user }}"
RP_DB_PASS="{{ .Data.data.postgres_pass }}"
RP_AMQP_USER="{{ .Data.data.rabbit_user }}"
RP_AMQP_PASS="{{ .Data.data.rabbit_pass }}"
RP_AMQP_APIUSER="{{ .Data.data.rabbit_user }}"
RP_AMQP_APIPASS="{{ .Data.data.rabbit_pass }}"
RP_INITIAL_ADMIN_PASSWORD="{{ .Data.data.initial_password }}"
{{ end }}
JAVA_OPTS="-Djava.security.egd=file:/dev/./urandom -XX:MinRAMPercentage=60.0 -XX:MaxRAMPercentage=90.0 --add-opens=java.base/java.lang=ALL-UNNAMED"
RP_SESSION_LIVE=86400
RP_INITIAL_ADMIN_PASSWORD=erebus
        EOF
        destination = "local/uat.env"
        env         = true
      }
      service {
        name = "uat"
        port = "uat"
        check {
          type     = "http"
          path     = "/health"
          interval = "60s"
          timeout  = "30s"
        }
      }
    }
  }
}
#   }  // group
# }
