# Monolithic deployment definition for Report Portal
# Does not depend on anything.
# Deploys backing services and application services in the same deployment
# Since the application services depend on the backing services,
# we should add a few prestart jobs to wait for them to be ready.
job "report-portal-services" {
  ui {
    description = "Report Portal Monolithic Deployment. Deploys all services necessary for a functional Report portal.\n\nSecond line."
    link {
      label = "Report Portal"
      url   = "https://reportportal.io"
    }
    link {
      label = "Report Portal Documentation"
      url   = "https://reportportal.io/docs"
    }
  }
  datacenters = ["dc1"]
  type        = "service"

  update {
    max_parallel      = 2
    health_check      = "checks"
    min_healthy_time  = "10s"
    healthy_deadline  = "10m"
    progress_deadline = "15m"
    auto_revert       = true
    auto_promote      = true
    canary            = 1
    stagger           = "30s"
  }

  reschedule {
    delay          = "30s"
    delay_function = "exponential"
    max_delay      = "1h"
    unlimited      = true
  }

  group "backing-services" {
    # The backing services group contains:
    # Gateway
    # ports:
    # - "8080:8080"  ## ReportPortal UI
    # - "8081:8081"  ## Traefik dashboard
    # - "443:443"
    # postgres Database
    # ports:
    #
    # opensearch
    # Rabbitmq
    network {
      port "gateway-dashboard" {
        static = 8081
      }
      port "report-portal-ui" {
        static = 8080
      }
      port "report-portal-postgres" {
        static = 5432
      }
      port "rabbitmq" {
        static = 5672
      }
      port "rabbit-api" {
        static = 15672
      }
      port "opensearch" {
        static = 9200
      }
      port "jobs" {
        static = 8686
      }
      port "report-portal-api" {
        static = 8585
      }
    }
    task "gateway" {
      vault {}
      resources {
        cpu    = 100
        memory = 256
      }
      driver = "docker"
      config {
        image = "traefik:v3.7.19"
        args  = ["--configFile=/etc/traefik/traefik.yml"]
        ports = ["gateway-dashboard"]
        volumes = [
          "local/traefik.toml:/etc/traefik/traefik.toml"
        ]
      }
      template {
        data        = <<EOF
accesslog = true
[log]
  level = "INFO"
[entryPoints]
  [entryPoints.http]
  address = ":8080"
  [entryPoints.traefik]
  address = ":8081"
[api]
  dashboard = true
  insecure = true
# Enable the Consul Catalog configuration backend
[providers.consulCatalog]
  prefix = "traefik"
  exposedByDefault = false
  [providers.consulCatalog.endpoint]
    address = "172.17.0.1:8500"
    scheme = "http"
{{ with secret "hashi_at_home/creds/report_portal"}}
    token = "{{ .Data.token }}"
{{ end }}
EOF
        destination = "local/traefik.toml"
      }
      shutdown_delay = "5s"
      service {
        port = "gateway-dashboard"
        check {
          type     = "http"
          name     = "report-portal-gateway-health"
          path     = "api/http/routers"
          interval = "10s"
          timeout  = "2s"
        }
      }

    }
    task "postgres" {
      vault {}
      resources {
        cpu    = 200
        memory = 512
      }
      driver = "docker"
      config {
        image = "postgres:18.6"
        ports = ["report-portal-postgres"]
      }
      shutdown_delay = "20s"
      service {
        port = "report-portal-postgres"
        name = "report-portal-postgres"
        check {
          name     = "report-portal-postgres-healthy"
          type     = "script"
          command  = "pg_isready"
          args     = ["-d", "$POSTGRES_DB", "-U", "$POSTGRES_USER"]
          interval = "10s"
          timeout  = "5s"
        }
      }
      template {
        change_mode = "noop"
        # Secrets for the postgres database
        # These are read from Vault in hashiatho.me-v2/report_portal
        data        = <<EOT
{{ with secret "hashiatho.me-v2/report_portal" }}
POSTGRES_USER="{{ .Data.data.postgres_user }}"
POSTGRES_PASSWORD="{{ .Data.data.postgres_pass }}"
POSTGRES_DB="reportportal"
{{ end }}
      EOT
        env         = true
        destination = "local/postgres.env"
      }
    }

    task "rabbit" {
      vault {}
      shutdown_delay = "10s"
      resources {
        cpu    = 100
        memory = 256
      }
      driver = "docker"
      config {
        image = "rabbitmq:4.4.0-management"
        ports = ["rabbitmq", "rabbit-api"]
        volumes = [
          "local/enabled_plugins:/etc/rabbitmq/enabled_plugins"
        ]
      }

      template {
        data        = <<EOT
  [rabbitmq_management,rabbitmq_consistent_hash_exchange,rabbitmq_auth_backend_ldap,rabbitmq_shovel,rabbitmq_shovel_management].
      EOT
        destination = "local/enabled_plugins"
      }

      template {
        data        = <<EOT
{{ with secret "hashiatho.me-v2/report_portal" }}
RABBITMQ_DEFAULT_USER="{{ .Data.data.rabbit_user }}"
RABBITMQ_DEFAULT_PASS="{{ .Data.data.rabbit_pass }}"
RABBITMQ_ERLANG_COOKIE=reportportal
{{ end }}
      EOT
        destination = "local/rabbit.env"
        env         = true
      }

      service {
        name = "report-portal-rabbit-amqp"
        port = "rabbitmq"
        # check {
        #   name = "report-portal-rabbitmq-alive"
        #   type = "script"
        #   command = "rabbitmq-diagnostics"
        #   args = ["-q", "--erlang-cookie", "reportportal", "ping"]
        #   interval = "10s"
        #   timeout = "2s"
        # }
      }
      service {
        name = "report-portal-rabbit-api"
        port = "rabbit-api"
        # check {
        #   name = "report-portal-rabbitmq-alive"
        #   type = "script"
        #   command = "rabbitmq-diagnostics"
        #   args = ["-q", "ping"]
        #   interval = "10s"
        #   timeout = "2s"
        # }
      }
    }

    task "opensearch" {
      vault {}
      shutdown_delay = "30s"

      resources {
        cpu    = 2000
        memory = 1600
      }
      driver = "docker"
      config {
        image = "opensearchproject/opensearch:3.9.0"
        ports = ["opensearch"]
      }
      template {
        data        = <<EOT
discovery.type=single-node
plugins.security.disabled="true"
bootstrap.memory_lock="true"
OPENSEARCH_JAVA_OPTS="-Xms512m -Xmx512m"
DISABLE_INSTALL_DEMO_CONFIG="true"
      EOT
        destination = "local/opensearch.env"
        env         = true
      }
      service {
        name = "report-portal-opensearch"
        port = "opensearch"
        check {
          name     = "report-portal-opensearch-healthy"
          type     = "http"
          path     = "_cluster/health"
          interval = "15s"
          timeout  = "5s"
        }
      }
    }

    task "migrations" {
      vault {}
      lifecycle {
        hook = "poststart"
      }
      driver = "docker"
      config {
        image = "reportportal/migrations:6.0.0"
      }
      env {
        POSTGRES_SERVER = "${NOMAD_IP_report-portal-postgres}"
        POSTGRES_PORT   = "${NOMAD_PORT_report-portal-postgres}"
      }
      template {
        data        = <<EOT
{{- with secret "hashiatho.me-v2/report_portal" }}
POSTGRES_DB=reportportal
POSTGRES_USER="{{ .Data.data.postgres_user }}"
POSTGRES_PASSWORD="{{ .Data.data.postgres_pass }}"
{{ end -}}
        EOT
        destination = "local/migrations.env"
        env         = true
        change_mode = "restart"
      }
    }

    task "jobs" {
      resources {
        cpu    = 250
        memory = 1024
      }
      driver = "docker"
      lifecycle {
        hook = "poststart"
      }
      vault {}
      shutdown_delay = "20s"
      config {
        image = "reportportal/service-jobs:6.0.0"
        ports = ["jobs"]
      }
      service {
        port = "jobs"
        tags = [
          "traefik.enable=true",
          "traefik.http.middlewares.jobs-strip-prefix.stripprefix.prefixes=/jobs",
          "traefik.http.routers.jobs.middlewares=jobs-strip-prefix@consulCatalog",
          "traefik.http.routers.jobs.rule=PathPrefix(`/jobs`)",
          "traefik.http.routers.jobs.service=jobs",
          "traefik.http.routers.jobs.entrypoints=web",
          "traefik.http.routers.jobs-secure.middlewares=jobs-strip-prefix@consulCatalog",
          "traefik.http.routers.jobs-secure.rule=PathPrefix(`/jobs`)",
          "traefik.http.routers.jobs-secure.service=jobs",
          "traefik.http.services.jobs.loadbalancer.server.port=8686",
          "traefik.http.services.jobs.loadbalancer.server.scheme=http",
          "traefik.expose=true",
        ]
        check {
          name     = "report-portal-jobs-healthy"
          type     = "http"
          path     = "/health"
          interval = "10s"
          timeout  = "2s"
        }
      } // service

      env {
        # See https://github.com/reportportal/service-jobs/blob/develop/src/main/resources/application.yml
        RP_ENVIRONMENT_VARIABLE_CLEAN_ATTACHMENT_CRON             = "0 0 */24 * * *"
        RP_ENVIRONMENT_VARIABLE_CLEAN_LOG_CRON                    = "0 0 */24 * * *"
        RP_ENVIRONMENT_VARIABLE_CLEAN_LAUNCH_CRON                 = "0 0 */24 * * *"
        RP_ENVIRONMENT_VARIABLE_BATCH-SIZE                        = 10000
        RP_ENVIRONMENT_VARIABLE_CLEAN_STORAGE_CRON                = "0 0 */24 * * *"
        RP_ENVIRONMENT_VARIABLE_STORAGE_PROJECT_CRON              = "0 */5 * * * *"
        RP_ENVIRONMENT_VARIABLE_CLEAN_EXPIREDUSER_CRON            = "0 0 */24 * * *"
        RP_ENVIRONMENT_VARIABLE_CLEAN_EXPIREDUSER_RETENTIONPERIOD = 365
        RP_ENVIRONMENT_VARIABLE_NOTIFICATION_EXPIREDUSER_CRON     = "0 0 */24 * * *"
        RP_ENVIRONMENT_VARIABLE_CLEAN_EVENTS_RETENTIONPERIOD      = 365
        RP_ENVIRONMENT_VARIABLE_CLEAN_EVENTS_CRON                 = "0 30 05 * * *"
        RP_ENVIRONMENT_VARIABLE_CLEAN_STORAGE_CHUNKSIZE           = 20000
        RP_PROCESSING_LOG_MAXBATCHSIZE                            = 2000
        RP_PROCESSING_LOG_MAXBATCHTIMEOUT                         = 6000
        RP_AMQP_MAXLOGCONSUMER                                    = 1
        RP_AMQP_HOST                                              = "${NOMAD_IP_rabbitmq}"
        RP_AMQP_PORT                                              = "${NOMAD_PORT_rabbitmq}"
        RP_DB_URL                                                 = "jdbc:postgresql://${NOMAD_IP_report-portal-postgres}:${NOMAD_PORT_report-portal-postgres}/reportportal"
        RP_AMQP_ANALYZER-VHOST                                    = "analyzer"
        RP_AMQP_ADDRESSES                                         = "amqp://${RP_AMQP_USER}:${RP_AMQP_PASS}@${NOMAD_IP_rabbitmq}:${NOMAD_PORT_rabbitmq}"
        RP_AMQP_API_ADDRESS                                       = "http://${RP_AMQP_USER}:${RP_AMQP_PASS}@${NOMAD_IP_rabbit-api}:15672/api"
        JAVA_OPTS                                                 = "-Xmx512m  -Djava.security.egd=file:/dev/./urandom -XX:+UseG1GC -XX:+UseStringDeduplication -XX:G1ReservePercent=20 -XX:InitiatingHeapOccupancyPercent=60 -XX:MaxRAMPercentage=70.0 -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/tmp"
      }
      # Other environment variables need to be looked up and injected from Consul and Vault
      template {
        data        = <<EOT
{{- with secret "hashiatho.me-v2/report_portal" }}
RP_DB_NAME=reportportal
RP_DB_USER="{{ .Data.data.postgres_user }}"
RP_DB_PASS="{{ .Data.data.postgres_pass }}"
RP_AMQP_USER="{{ .Data.data.rabbit_user }}"
RP_AMQP_PASS="{{ .Data.data.rabbit_user }}"
RP_AMQP_APIUSER="{{ .Data.data.rabbit_user }}"
RP_AMQP_APIPASS="{{ .Data.data.rabbit_user }}"
{{ end -}}
          EOT
        destination = "local/jobs.env"
        env         = true
      }
    } // jobs task

    task "ui" {
      resources {
        cpu    = 100
        memory = 128
      }
      shutdown_delay = "5s"
      lifecycle {
        hook = "poststart"
      }
      driver = "docker"
      config {
        image = "reportportal/service-ui:6.0.0"
        ports = ["report-portal-ui"]
      }
      env {
        RP_SERVER_PORT = "8080"
      }
      service {
        name = "report-portal-ui"
        port = "report-portal-ui"
        tags = [
          "traefik.enable=true",
          "traefik.http.middlewares.ui-strip-prefix.stripprefix.prefixes=/ui",
          "traefik.http.routers.ui.middlewares=ui-strip-prefix",
          "traefik.http.routers.ui.rule=PathPrefix(`/ui`)",
          "traefik.http.routers.ui.service=ui",
          "traefik.http.routers.ui.entrypoints=web",
          "traefik.http.routers.ui-secure.middlewares=ui-strip-prefix@consulCatalog",
          "traefik.http.routers.ui-secure.rule=PathPrefix(`/ui`)",
          "traefik.http.routers.ui-secure.service=ui",
          "traefik.http.routers.ui-secure.entrypoints=websecure",
          "traefik.http.services.ui.loadbalancer.server.port=8080",
          "traefik.http.services.ui.loadbalancer.server.scheme=http",
          "traefik.http.routers.root.rule=PathPrefix(`/`)",
          "traefik.http.routers.root.priority=1",
          "traefik.http.routers.root.service=ui",
          "traefik.http.routers.root.entrypoints=web",
          "traefik.http.routers.root-secure.rule=PathPrefix(`/`)",
          "traefik.http.routers.root-secure.priority=1",
          "traefik.http.routers.root-secure.service=ui",
          "traefik.http.routers.root-secure.entrypoints=websecure",
          "traefik.expose=true"
        ]
        check {
          name     = "report-portal-ui-healthy"
          type     = "http"
          path     = "/health"
          interval = "15s"
          timeout  = "5s"
        }
      } // service
    }   // task ui

    task "api" {
      vault {}
      shutdown_delay = "30s"
      resources {
        cpu    = 1000
        memory = 1300
      }
      lifecycle {
        hook = "poststart"
      }
      driver = "docker"
      config {
        image = "reportportal/service-api:6.0.0"
        ports = ["report-portal-api"]
      }
      env {
        RP_DB_HOST                                               = "${NOMAD_IP_report-portal-postgres}"
        RP_DB_PORT                                               = "${NOMAD_PORT_report-portal-postgres}"
        RP_AMQP_HOST                                             = "${NOMAD_IP_rabbitmq}"
        RP_AMQP_PORT                                             = "${NOMAD_PORT_rabbitmq}"
        RP_AMQP_APIPORT                                          = "${NOMAD_PORT_rabbit-api}"
        RP_AMQP_ANALYZER-VHOST                                   = "analyzer"
        RP_AMQP_EXCHANGE_NAME                                    = "analyzer-default"
        RP_AMQP_VIRTUAL_HOST                                     = "analyzer"
        ES_HOSTS                                                 = "http://${NOMAD_IP_opensearch}:${NOMAD_PORT_opensearch}"
        LOGGING_LEVEL_ORG_HIBERNATE_SQL                          = "info"
        RP_REQUESTLOGGING                                        = "false"
        AUDIT_LOGGER                                             = "OFF"
        MANAGEMENT_HEALTH_ELASTICSEARCH_ENABLED                  = "false"
        RP_ENVIRONMENT_VARIABLE_ALLOW_DELETE_ACCOUNT             = "false"
        JAVA_OPTS                                                = "-Xmx1g -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/tmp -Dcom.sun.management.jmxremote.rmi.port=12349 -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.local.only=false -Dcom.sun.management.jmxremote.port=9010 -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Djava.rmi.server.hostname=0.0.0.0"
        RP_JOBS_BASEURL                                          = "http://${NOMAD_IP_jobs}:${NOMAD_PORT_jobs}"
        COM_TA_REPORTPORTAL_JOB_INTERRUPT_BROKEN_LAUNCHES_CRON   = "PT1H"
        RP_ENVIRONMENT_VARIABLE_PATTERN-ANALYSIS_BATCH-SIZE      = 100
        RP_ENVIRONMENT_VARIABLE_PATTERN-ANALYSIS_PREFETCH-COUNT  = 1
        RP_ENVIRONMENT_VARIABLE_PATTERN-ANALYSIS_CONSUMERS-COUNT = 1
        COM_TA_REPORTPORTAL_JOB_LOAD_PLUGINS_CRON                = "PT10S"
        COM_TA_REPORTPORTAL_JOB_CLEAN_OUTDATED_PLUGINS_CRON      = "PT10S"
        REPORTING_QUEUES_COUNT                                   = 10
        REPORTING_CONSUMER_PREFETCHCOUNT                         = 10
        REPORTING_PARKINGLOT_TTL_DAYS                            = 7
        RP_SESSION_LIVE                                          = 86400 ## Session duration in seconds (1 day)
        RP_SAML_SESSION-LIVE                                     = 4320  ## SAML session duration in minutes (3 days)
      }                                                                  // env
      template {
        data        = <<EOT
{{ with secret "hashiatho.me-v2/report_portal" }}
RP_DB_USER={{ .Data.data.postgres_user }}
RP_DB_PASS={{ .Data.data.postgres_pass }}
RP_DB_NAME=reportportal
RP_AMQP_USER={{ .Data.data.rabbit_user }}
RP_AMQP_PASS={{ .Data.data.rabbit_pass }}
RP_AMQP_APIUSER={{ .Data.data.rabbit_user }}
RP_AMQP_APIPASS={{ .Data.data.rabbit_pass }}
RP_INITIAL_ADMIN_PASSWORD={{ .Data.data.rp_initial_password }}
{{ end -}}
        EOT
        destination = "local/api.env"
        env         = true
      } // template

      service {
        name = "report-portal-api"
        port = "report-portal-api"
        tags = [
          "traefik.enable=true",
          "traefik.http.middlewares.api-strip-prefix.stripprefix.prefixes=/api",
          "traefik.http.routers.api.middlewares=api-strip-prefix@consulCatalog",
          "traefik.http.routers.api.rule=PathPrefix(`/api`)",
          "traefik.http.routers.api.service=api",
          "traefik.http.routers.api.entrypoints=web",
          "traefik.http.routers.api-secure.middlewares=api-strip-prefix@consulCatalog",
          "traefik.http.routers.api-secure.rule=PathPrefix(`/api`)",
          "traefik.http.routers.api-secure.service=api",
          "traefik.http.routers.api-secure.entrypoints=websecure",
          "traefik.http.services.api.loadbalancer.server.port=8585",
          "traefik.http.services.api.loadbalancer.server.scheme=http",
          "traefik.expose=true",
        ]
        check {
          port     = "report-portal-api"
          type     = "http"
          path     = "/health"
          interval = "30s"
          timeout  = "10s"
        }
      } // service
    }   // task
  }     // group
}       // job
