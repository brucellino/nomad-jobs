variable "db_name" {
  type        = string
  default     = "reportportal"
  description = "Database name for Report Portal"
}

job "report-portal-services" {
  datacenters = ["dc1"]
  type        = "service"

  update {
    max_parallel      = 3
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

  group "rp-services" {
    count = 1

    network {
      mode = "host"
      port "index" {
        static = 8080
        to     = 8080
      }
      port "ui" {
        static = 8084
        to     = 8080
      }
      port "api" {
        static = 8585
        to     = 8585
      }
      port "uat" {
        static = 9999
        to     = 9999
      }
      port "jobs" {
        static = 8686
        to     = 8686
      }
      port "analyzer" {
        static = 5000
        to     = 5000
      }
      port "analyzer-train" {
        static = 5001
        to     = 5001
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
      attempts = 3
      delay    = "30s"
      mode     = "delay"
    }

    # Database cleanup task - removes plugin conflicts before API starts
    task "db-cleanup" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      vault {
        policies    = ["nomad-read"]
        change_mode = "restart"
        # change_signal = "SIGHUP"
      }

      template {
        data        = <<EOF
{{- range service "rp-db" }}
PGHOST={{ .Address }}
PGPORT={{ .Port }}
{{- end }}
PGDATABASE=${var.db_name}
{{- with secret "hashiatho.me-v2/data/report_portal" }}
PGUSER={{ .Data.data.postgres_user }}
PGPASSWORD={{ .Data.data.postgres_pass }}
{{- end }}
EOF
        destination = "local/db.env"
        env         = true
        change_mode = "restart"
        wait {
          min = "2s"
          max = "60s"
        }
      }

      config {
        image   = "postgres:12.17-alpine"
        command = "sh"
        args = [
          "-c",
          "psql \"postgresql://$PGUSER:$PGPASSWORD@$PGHOST:$PGPORT/$PGDATABASE\" -c \"DO \\$\\$ BEGIN IF EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'integration') THEN TRUNCATE TABLE integration CASCADE; END IF; IF EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'integration_type') THEN TRUNCATE TABLE integration_type CASCADE; END IF; END \\$\\$;\""
        ]
      }

      resources {
        cpu    = 256
        memory = 256
      }
    }

    # Index service - main entry point
    task "index" {
      driver = "docker"

      config {
        image = "reportportal/service-index:5.14.0"
        ports = ["index"]
      }

      env {
        LB_URL          = "http://traefik.service.consul:8081"
        TRAEFIK_V2_MODE = "true"
      }

      resources {
        cpu    = 256
        memory = 512
      }

      service {
        name     = "rp-index"
        port     = "index"
        provider = "consul"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.rp-index.rule=PathPrefix('/')",
          "traefik.http.routers.rp-index.rule=Path(`/`)",
          "traefik.http.routers.rp-index.entrypoints=http",
          "traefik.http.routers.rp-index.service=rp-index",
          "traefik.http.services.rp-index.loadbalancer.server.port=8080",
          "traefik.http.services.rp-index.loadbalancer.server.scheme=http"
        ]

        check {
          port     = "index"
          name     = "index-health"
          type     = "http"
          path     = "/health"
          interval = "20s"
          timeout  = "5s"
        }
      }
    }

    # UI service - web interface
    task "ui" {
      driver = "docker"

      config {
        image = "reportportal/service-ui:5.14.2"
        ports = ["ui"]
      }

      env {
        RP_SERVER_PORT = "8080"
      }

      resources {
        cpu    = 512
        memory = 1024
      }

      service {
        name     = "rp-ui"
        port     = "ui"
        provider = "consul"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.rp-ui.rule=PathPrefix('/ui')",
          "traefik.http.routers.rp-ui.rule=PathPrefix(`/ui`)",
          "traefik.http.routers.rp-ui.entrypoints=http",
          "traefik.http.routers.rp-ui.middlewares=rp-ui-strip-prefix",
          "traefik.http.middlewares.rp-ui-strip-prefix.stripprefix.prefixes=/ui",
          "traefik.http.routers.rp-ui.service=rp-ui",
          "traefik.http.services.rp-ui.loadbalancer.server.port=8084",
          "traefik.http.services.rp-ui.loadbalancer.server.scheme=http"
        ]

        check {
          port     = "ui"
          name     = "ui-health"
          type     = "http"
          path     = "/health"
          interval = "30s"
          timeout  = "10s"
        }
      }
    }

    # API service - backend API
    task "api" {
      driver = "docker"

      config {
        image = "reportportal/service-api:5.14.0"
        ports = ["api"]
      }



      vault {
        policies      = ["nomad-read"]
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }

      template {
        data        = <<EOF
{{- range service "rp-db" }}
RP_DB_HOST={{ .Address }}
RP_DB_PORT={{ .Port }}
{{- end }}
{{- range service "rp-rabbit" }}
RP_AMQP_HOST={{ .Address }}
RP_AMQP_PORT={{ .Port }}
{{- end }}
{{- range service "rp-rabbit-management" }}
RP_AMQP_APIPORT={{ .Port }}
{{- end }}
RP_DB_NAME=${var.db_name}
RP_AMQP_ANALYZER_VHOST=analyzer
{{- with secret "hashiatho.me-v2/data/report_portal" }}
RP_DB_USER={{ .Data.data.postgres_user }}
RP_DB_PASS={{ .Data.data.postgres_pass }}
RP_AMQP_USER={{ .Data.data.rabbit_user }}
RP_AMQP_PASS={{ .Data.data.rabbit_pass }}
RP_AMQP_APIUSER={{ .Data.data.rabbit_user }}
RP_AMQP_APIPASS={{ .Data.data.rabbit_pass }}
{{- end }}
RP_JOBS_BASEURL=http://{{ env "NOMAD_ADDR_jobs" }}
EOF
        destination = "local/api.env"
        env         = true
        change_mode = "noop"
        wait {
          min = "2s"
          max = "60s"
        }
      }

      env {
        DATASTORE_TYPE                                           = "filesystem"
        LOGGING_LEVEL_ORG_HIBERNATE_SQL                          = "info"
        RP_REQUESTLOGGING                                        = "false"
        AUDIT_LOGGER                                             = "OFF"
        MANAGEMENT_HEALTH_ELASTICSEARCH_ENABLED                  = "false"
        RP_ENVIRONMENT_VARIABLE_ALLOW_DELETE_ACCOUNT             = "false"
        JAVA_OPTS                                                = "-Xmx1g -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/tmp -Dcom.sun.management.jmxremote.rmi.port=12349 -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.local.only=false -Dcom.sun.management.jmxremote.port=9010 -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Djava.rmi.server.hostname=0.0.0.0 -Dspring.main.allow-bean-definition-overriding=true"
        COM_TA_REPORTPORTAL_JOB_INTERRUPT_BROKEN_LAUNCHES_CRON   = "PT1H"
        RP_ENVIRONMENT_VARIABLE_PATTERN_ANALYSIS_BATCH_SIZE      = "100"
        RP_ENVIRONMENT_VARIABLE_PATTERN_ANALYSIS_PREFETCH_COUNT  = "1"
        RP_ENVIRONMENT_VARIABLE_PATTERN_ANALYSIS_CONSUMERS_COUNT = "1"
        REPORTING_QUEUES_COUNT                                   = "10"
        REPORTING_CONSUMER_PREFETCHCOUNT                         = "10"
        REPORTING_PARKINGLOT_TTL_DAYS                            = "7"
        # Disable plugin loading entirely
        # RP_PLUGIN_STARTUP_ENABLED = "false"
        LOGGING_LEVEL_COM_EPAM_TA_REPORTPORTAL_PLUGIN = "OFF"
      }

      resources {
        cpu    = 2048
        memory = 2048
      }

      volume_mount {
        volume      = "storage"
        destination = "/data/storage"
      }

      service {
        name     = "rp-api"
        port     = "api"
        provider = "consul"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.rp-api.rule=Path(`api`)",
          "traefik.http.routers.rp-api.rule=PathPrefix(`/api`)",
          "traefik.http.routers.rp-api.entrypoints=http",
          "traefik.http.routers.rp-api.middlewares=rp-api-strip-prefix",
          "traefik.http.middlewares.rp-api-strip-prefix.stripprefix.prefixes=/api",
          "traefik.http.routers.rp-api.service=rp-api",
          "traefik.http.services.rp-api.loadbalancer.server.port=8585",
          "traefik.http.services.rp-api.loadbalancer.server.scheme=http"
        ]

        check {
          name     = "api-health"
          type     = "http"
          path     = "/health"
          interval = "60s"
          timeout  = "20s"
        }
      }
    }

    # UAT service - authorization and authentication
    task "uat" {
      driver = "docker"
      lifecycle {
        hook = "poststart"
      }
      config {
        image = "reportportal/service-authorization:5.13.2"
        ports = ["uat"]
      }

      vault {
        policies      = ["nomad-read"]
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }

      template {
        data        = <<EOF
{{- range service "rp-db" }}
RP_DB_HOST={{ .Address }}
RP_DB_PORT={{ .Port }}
{{- end }}
{{- range service "rp-rabbit" }}
RP_AMQP_HOST={{ .Address }}
RP_AMQP_PORT={{ .Port }}
{{- end }}
{{- range service "rp-rabbit-management" }}
RP_AMQP_APIPORT={{ .Port }}
{{- end }}
RP_DB_NAME=${var.db_name}
DATASTORE_TYPE=filesystem
RP_AMQP_ANALYZER_VHOST=analyzer
{{- with secret "hashiatho.me-v2/data/report_portal" }}
RP_DB_USER={{ .Data.data.postgres_user }}
RP_DB_PASS={{ .Data.data.postgres_pass }}
RP_AMQP_USER={{ .Data.data.rabbit_user }}
RP_AMQP_PASS={{ .Data.data.rabbit_pass }}
RP_AMQP_APIUSER={{ .Data.data.rabbit_user }}
RP_AMQP_APIPASS={{ .Data.data.rabbit_pass }}
RP_INITIAL_ADMIN_PASSWORD={{ .Data.data.rp_initial_password }}
{{- end }}
EOF
        destination = "local/uat.env"
        env         = true
        change_mode = "restart"
        wait {
          min = "2s"
          max = "60s"
        }
      }

      env {
        RP_SESSION_LIVE      = "86400"
        RP_SAML_SESSION-LIVE = "4320"
        JAVA_OPTS            = "-Djava.security.egd=file:/dev/./urandom -XX:MinRAMPercentage=60.0 -XX:MaxRAMPercentage=90.0 --add-opens=java.base/java.lang=ALL-UNNAMED"
      }

      resources {
        cpu    = 1024
        memory = 1024
      }
      volume_mount {
        volume      = "storage"
        destination = "/data/storage"
      }

      service {
        name     = "rp-uat"
        port     = "uat"
        provider = "consul"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.rp-uat.rule=Path(`/uat`)",
          "traefik.http.routers.rp-uat.rule=PathPrefix(`/uat`)",
          "traefik.http.routers.rp-uat.entrypoints=http",
          "traefik.http.routers.rp-uat.middlewares=rp-uat-strip-prefix",
          "traefik.http.middlewares.rp-uat-strip-prefix.stripprefix.prefixes=/uat",
          "traefik.http.routers.rp-uat.service=rp-uat",
          "traefik.http.services.rp-uat.loadbalancer.server.port=9999",
          "traefik.http.services.rp-uat.loadbalancer.server.scheme=http"
        ]

        check {
          name     = "uat-health"
          type     = "http"
          path     = "/health"
          interval = "60s"
          timeout  = "20s"
        }
      }
    }

    # Jobs service - scheduled job processor
    task "jobs" {
      driver = "docker"

      config {
        image = "reportportal/service-jobs:5.14.0"
        ports = ["jobs"]
      }

      vault {
        policies      = ["nomad-read"]
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }

      template {
        data        = <<EOF
{{- range service "rp-db" }}
RP_DB_HOST={{ .Address }}
RP_DB_PORT={{ .Port }}
{{- end }}
{{- range service "rp-rabbit" }}
RP_AMQP_HOST={{ .Address }}
RP_AMQP_PORT={{ .Port }}
{{- end }}
{{- range service "rp-rabbit-management" }}
RP_AMQP_APIPORT={{ .Port }}
{{- end }}
RP_DB_NAME=${var.db_name}
RP_AMQP_ANALYZER_VHOST=analyzer
{{- with secret "hashiatho.me-v2/data/report_portal" }}
RP_DB_USER={{ .Data.data.postgres_user }}
RP_DB_PASS={{ .Data.data.postgres_pass }}
RP_AMQP_USER={{ .Data.data.rabbit_user }}
RP_AMQP_PASS={{ .Data.data.rabbit_pass }}
RP_AMQP_APIUSER={{ .Data.data.rabbit_user }}
RP_AMQP_APIPASS={{ .Data.data.rabbit_pass }}
{{- end }}
EOF
        destination = "local/jobs.env"
        env         = true
        change_mode = "noop"
        wait {
          min = "2s"
          max = "60s"
        }
      }

      env {
        DATASTORE_TYPE                                            = "filesystem"
        RP_ENVIRONMENT_VARIABLE_CLEAN_ATTACHMENT_CRON             = "0 0 */24 * * *"
        RP_ENVIRONMENT_VARIABLE_CLEAN_LOG_CRON                    = "0 0 */24 * * *"
        RP_ENVIRONMENT_VARIABLE_CLEAN_LAUNCH_CRON                 = "0 0 */24 * * *"
        RP_ENVIRONMENT_VARIABLE_CLEAN_STORAGE_CRON                = "0 0 */24 * * *"
        RP_ENVIRONMENT_VARIABLE_STORAGE_PROJECT_CRON              = "0 */5 * * * *"
        RP_ENVIRONMENT_VARIABLE_CLEAN_EXPIREDUSER_CRON            = "0 0 */24 * * *"
        RP_ENVIRONMENT_VARIABLE_CLEAN_EXPIREDUSER_RETENTIONPERIOD = "365"
        RP_ENVIRONMENT_VARIABLE_NOTIFICATION_EXPIREDUSER_CRON     = "0 0 */24 * * *"
        RP_ENVIRONMENT_VARIABLE_CLEAN_EVENTS_RETENTIONPERIOD      = "365"
        RP_ENVIRONMENT_VARIABLE_CLEAN_EVENTS_CRON                 = "0 30 05 * * *"
        RP_ENVIRONMENT_VARIABLE_CLEAN_STORAGE_CHUNKSIZE           = "20000"
        RP_PROCESSING_LOG_MAXBATCHSIZE                            = "2000"
        RP_PROCESSING_LOG_MAXBATCHTIMEOUT                         = "6000"
        RP_AMQP_MAXLOGCONSUMER                                    = "1"
        JAVA_OPTS                                                 = "-Djava.security.egd=file:/dev/./urandom -XX:+UseG1GC -XX:+UseStringDeduplication -XX:G1ReservePercent=20 -XX:InitiatingHeapOccupancyPercent=60 -XX:MaxRAMPercentage=70.0 -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/tmp"
      }

      resources {
        cpu    = 1024
        memory = 1024
      }

      volume_mount {
        volume      = "storage"
        destination = "/data/storage"
      }

      service {
        name     = "rp-jobs"
        port     = "jobs"
        provider = "consul"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.rp-jobs.rule=PathPrefix(`/jobs`)",
          "traefik.http.routers.rp-jobs.rule=Path(`/jobs`)",
          "traefik.http.routers.rp-jobs.entrypoints=http",
          "traefik.http.routers.rp-jobs.middlewares=rp-jobs-strip-prefix",
          "traefik.http.middlewares.rp-jobs-strip-prefix.stripprefix.prefixes=/jobs",
          "traefik.http.routers.rp-jobs.service=rp-jobs",
          "traefik.http.services.rp-jobs.loadbalancer.server.port=8686",
          "traefik.http.services.rp-jobs.loadbalancer.server.scheme=http"
        ]

        check {
          name     = "jobs-health"
          type     = "http"
          path     = "/health"
          interval = "60s"
          timeout  = "20s"
        }
      }
    }

    # Analyzer service - automatic test result analysis (optional)
    task "analyzer" {
      driver = "docker"

      config {
        image = "reportportal/service-auto-analyzer:5.14.0"
        ports = ["analyzer"]
      }

      template {
        data        = <<EOF
{{- with secret "hashiatho.me-v2/data/report_portal" }}
{{- $rabbit_user := .Data.data.rabbit_user }}
{{- $rabbit_pass := .Data.data.rabbit_pass }}
{{- range service "rp-rabbit" }}
AMQP_URL=amqp://{{ $rabbit_user }}:{{ $rabbit_pass }}@{{ .Address }}:{{ .Port }}
{{- end }}
{{- end }}
{{- range service "rp-opensearch" }}
ES_HOSTS=http://{{ .Address }}:{{ .Port }}
{{- end }}
EOF
        destination = "local/analyzer.env"
        env         = true
        change_mode = "noop"
        wait {
          min = "2s"
          max = "60s"
        }
      }

      env {
        LOGGING_LEVEL             = "info"
        AMQP_EXCHANGE_NAME        = "analyzer-default"
        AMQP_VIRTUAL_HOST         = "analyzer"
        ANALYZER_BINARYSTORE_TYPE = "filesystem"
      }

      resources {
        cpu    = 512
        memory = 1024
      }

      volume_mount {
        volume      = "storage"
        destination = "/data/storage"
      }

      # service {
      #   name = "rp-analyzer"
      #   port = "analyzer"
      #   provider = "consul"

      #   check {
      #     name     = "analyzer-health"
      #     type     = "tcp"
      #     interval = "60s"
      #     timeout  = "10s"
      #   }
      # }
    }

    # Analyzer Train service - ML training for analysis (optional)
    task "analyzer-train" {
      driver = "docker"

      config {
        image = "reportportal/service-auto-analyzer:5.14.0"
        ports = ["analyzer-train"]
      }

      template {
        data        = <<EOF
{{- with secret "hashiatho.me-v2/data/report_portal" }}
{{- $rabbit_user := .Data.data.rabbit_user }}
{{- $rabbit_pass := .Data.data.rabbit_pass }}
{{- range service "rp-rabbit" }}
AMQP_URL=amqp://{{ $rabbit_user }}:{{ $rabbit_pass }}@{{ .Address }}:{{ .Port }}
{{- end }}
{{- end }}
{{- range service "rp-opensearch" }}
ES_HOSTS=http://{{ .Address }}:{{ .Port }}
{{- end }}
EOF
        destination = "local/analyzer-train.env"
        env         = true
        change_mode = "noop"
        wait {
          min = "2s"
          max = "60s"
        }
      }

      env {
        LOGGING_LEVEL             = "info"
        AMQP_EXCHANGE_NAME        = "analyzer-default"
        AMQP_VIRTUAL_HOST         = "analyzer"
        ANALYZER_BINARYSTORE_TYPE = "filesystem"
        INSTANCE_TASK_TYPE        = "train"
        UWSGI_WORKERS             = "1"
      }

      resources {
        cpu    = 512
        memory = 1024
      }

      volume_mount {
        volume      = "storage"
        destination = "/data/storage"
      }

      # service {
      #   name = "rp-analyzer-train"
      #   port = "analyzer-train"
      #   provider = "consul"

      #   check {
      #     name     = "analyzer-train-health"
      #     type     = "tcp"
      #     interval = "60s"
      #     timeout  = "10s"
      #   }
      # }
    }
  }
}
