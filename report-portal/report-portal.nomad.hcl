variable "db" {
  type = object({
    image   = string
    version = string
    port    = number
    db_name = string
  })
  default = {
    image   = "bitnami/postgresql"
    version = "16.6.0"
    port    = 5432
    db_name = "reportportal"
  }
  description = "Database configuration"
}

variable "rabbitmq" {
  type = object({
    image   = string
    version = string
    port    = number
  })
  default = {
    image      = "bitnami/rabbitmq"
    version    = "3.13.7-debian-12-r5"
    port       = 5672
    queue_name = "reportportal"
  }
  description = "RabbitMQ configuration"
}

variable "opensearch" {
  type = object({
    image   = string
    version = string
    port    = number
  })
  default = {
    image   = "opensearchproject/opensearch"
    version = "3"
    port    = 9200
  }
  description = "OpenSearch configuration"
}

job "report-portal" {
  reschedule {
    delay          = "30s"
    delay_function = "exponential"
    max_delay      = "1h"
    unlimited      = true
  }
  group "rp-backend" {
    network {
      port "db" {
        to = var.db.port
      }
      port "opensearch" {
        to = var.opensearch.port
      }
    }
    # vault {
    #   policies = ["nomad-read", "nomad-workloads", "default"]
    #   change_mode = "noop"
    #   env = true
    # }
    // Tasks which require peristent storage and provide backend functionality
    // These include the DB and the API


    task "db" {
      env {
        POSTGRES_DB = var.db.db_name
      }
      vault {
        policies      = ["nomad-read"]
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }
      template {
        data        = <<EOF
{{ with secret "hashiatho.me-v2/data/report_portal" }}
POSTGRES_USER="{{ .Data.data.postgres_user }}"
POSTGRES_PASSWORD="{{ .Data.data.postgres_pass }}"
{{ end }}
        EOF
        destination = "${NOMAD_SECRETS_DIR}/db.env"
        env         = true
      }
      driver = "docker"
      config {
        image = "${var.db.image}:${var.db.version}"
        ports = ["db"]
      }
      resources {
        cpu    = 500
        memory = 512
      }
      service {
        provider = "consul"
        port     = "db"
        tags     = ["db"]
        check {
          type     = "script"
          command  = "pg_isready"
          args     = ["-d", "$POSTGRES_DB", "-U", "$POSTGRES_USER"]
          interval = "20s"
          timeout  = "5s"
        }
      }
    }

    task "migrations" {
      driver = "docker"
      vault {
        policies      = ["nomad-read"]
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }
      resources {
        cpu    = 256
        memory = 128
      }
      template {
        data        = <<EOF
{{ with secret "hashiatho.me-v2/data/report_portal" }}
POSTGRES_USER="{{ .Data.data.postgres_user }}"
POSTGRES_PASSWORD="{{ .Data.data.postgres_pass }}"
{{ end }}
POSTGRES_SERVER="{{ env "NOMAD_IP_db" }}"
POSTGRES_PORT="{{ env "NOMAD_HOST_PORT_db" }}"
POSTGRES_DB="${var.db.db_name}"
        EOF
        destination = "${NOMAD_SECRETS_DIR}/task.env"
        env         = true
      }
      config {
        image = "reportportal/migrations:5.14.0"
      }
      lifecycle {
        hook = "poststart"
      }
    }

    task "opensearch" {
      service {
        port = "opensearch"
        check {
          name     = "opensearch"
          type     = "http"
          path     = "/_cat/health"
          interval = "10s"
          timeout  = "2s"
        }
      }
      env = {
        "discovery.type"              = "single-node"
        "plugins.security.disabled"   = true
        "bootstrap.memory_lock"       = true
        "OPENSEARCH_JAVA_OPTS"        = "-Xms512m -Xmx512m"
        "DISABLE_INSTALL_DEMO_CONFIG" = true
      }
      driver = "docker"
      config {
        image = "${var.opensearch.image}:${var.opensearch.version}"
        ulimit {
          memlock = "-1:-1"
        }
        ports = ["opensearch"]
      }
      resources {
        cores  = 1
        memory = 1024
      }

      // for rpi5
      constraint {
        attribute = "${attr.unique.hostname}"
        value     = "ticklish"
      }
    }
  }

  group "rp-glue" {
    network {
      port "rabbit" {
        to = "5672"
      }
      port "management" {
        to = "15672"
      }
      port "lb" {
        to = "8080"
      }
      port "traefik-management" {
        to = "8081"
      }
    }

    task "traefik" {
      driver = "docker"
      config {
        image = "traefik:v2.11.24"
        args = [
          # "--providers.consul=true",
          # "--providers.consul.endpoints=127.0.0.1:8500",
          "--entrypoints.web.address=:8080", "--entrypoints.traefik.address=:8081",
          "--api.dashboard=true",
          "--api.insecure=true"
        ]
        ports = ["traefik-management", "lb"]
      }
      service {
        name = "report-portal-traefik"
        port = "traefik-management"
        tags = ["traefik-public"]
      }
    }

    task "rabbit" {
      vault {
        policies      = ["nomad-read"]
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }
      template {
        data        = <<EOF
{{ with secret "hashiatho.me-v2/data/report_portal" }}
RABBITMQ_USER="{{ .Data.data.rabbit_user }}"
RABBITMQ_PASSWORD="{{ .Data.data.rabbit_pass }}"
RABBITMQ_MANAGEMENT_ALLOW_WEB_ACCESS="true"
RABBITMQ_DISK_FREE_ABSOLUTE_LIMIT="50MB"
RABBITMQ_PLUGINS="rabbitmq_consistent_hash_exchange rabbitmq_management rabbitmq_auth_backend_ldap rabbitmq_shovel rabbitmq_shovel_management"
{{ end }}
        EOF
        destination = "${NOMAD_SECRETS_DIR}/rabbitmq.env"
        env         = true
      }
      driver = "docker"
      config {
        image = "${var.rabbitmq.image}:${var.rabbitmq.version}"
        ports = ["rabbit", "management"]
      }
      resources {
        cpu    = 256
        memory = 512
      }
      service {
        name = "report-portal-rp-glue-rabbit"
        port = "rabbit"
        check {
          type     = "script"
          command  = "rabbitmqctl"
          args     = ["status"]
          interval = "30s"
          timeout  = "5s"
        }
      }

      service {
        name = "report-portal-rp-glue-rabbit-management"
        port = "management"
        check {
          type     = "http"
          path     = "/api"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }
  }

  group "rp-frontend" {
    network {
      port "index" {
        to = "8080"
      }
      port "ui" {
        to = "8080"
      }
      port "api" {
        to = "8585"
      }
      port "uat" {
        to = "9999"
      }
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
        port = "index"

        check {
          name     = "index"
          type     = "http"
          path     = "/health"
          interval = "10s"
          timeout  = "2s"
        }
      }
      env {
        LB_URL          = "http://gateway:8081"
        TRAEFIK_V2_MODE = true
      }
      driver = "docker"
      config {
        image = "reportportal/service-index:5.14.0"
        ports = ["index"]
      }
    }

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
        RP_SERVER_PORT = "${NOMAD_HOST_PORT_index}"
      }
      driver = "docker"
      config {
        image = "reportportal/service-ui:5.14.2"
        ports = ["ui"]
      }
    }

    task "api" {
      driver = "docker"
      vault {
        policies      = ["nomad-read"]
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }
      lifecycle {
        hook = "poststart"
      }
      service {
        port = "api"
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
        image = "reportportal/service-api:5.14.1"
        ports = ["api"]
      }

      resources {
        cores  = 2
        memory = 2048
      }
      template {
        data        = <<EOF
RP_DB_HOST="{{- range service "report-portal-rp-backend-db" }}{{ .Address }}{{ end }}"
RP_DB_PORT="{{- range service "report-portal-rp-backend-db" }}{{ .Port }}{{ end }}"
{{ with secret "hashiatho.me-v2/data/report_portal" }}
RP_DB_USER="{{ .Data.data.postgres_user }}"
RP_DB_PASS="{{ .Data.data.postgres_pass }}"
RP_AMQP_USER="{{ .Data.data.rabbit_user }}"
RP_AMQP_PASS="{{ .Data.data.rabbit_pass }}"
RP_AMQP_APIUSER="{{ .Data.data.rabbit_user }}"
RP_AMQP_APIPASS="{{ .Data.data.rabbit_pass }}"
{{ end }}
RP_DB_NAME="${var.db.db_name}"
RP_AMQP_HOST="{{- range service "report-portal-rp-glue-rabbit" }}{{ .Address }}{{ end }}"
RP_AMQP_PORT="{{- range service "report-portal-rp-glue-rabbit" }}{{ .Port }}{{ end }}"
RP_AMQP_APIPORT="{{- range service "report-portal-rp-glue-rabbit-management" }}{{ .Port }}{{ end }}"
RP_JOBS_BASEURL="http://jobs:8686"
        EOF
        destination = "${NOMAD_SECRETS_DIR}/api.env"
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
    }

    task "uat" {
      driver = "docker"
      vault {
        policies      = ["nomad-read"]
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }
      config {
        image = "service-authorization:5.14.3"
        ports = ["uat"]
      }
      template {
        data        = <<EOF
RP_DB_HOST="{{- range service "report-portal-rp-backend-db" }}{{ .Address }}{{ end }}"
RP_DB_PORT="{{- range service "report-portal-rp-backend-db" }}{{ .Port }}{{ end }}"
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
        EOF
        destination = "${NOMAD_SECRETS_DIR}/uat.env"
        env         = true
      }
    }
  }

  group "backend-jobs" {
    network {
      port "job" {
        to = 8686
      }
    }
    task "job" {
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
      template {
        data        = <<EOF
RP_DB_HOST="{{- range service "report-portal-rp-backend-db" }}{{ .Address }}{{ end }}"
RP_DB_PORT="{{- range service "report-portal-rp-backend-db" }}{{ .Port }}{{ end }}"
{{ with secret "hashiatho.me-v2/data/report_portal" }}
RP_DB_USER="{{ .Data.data.postgres_user }}"
RP_DB_PASS="{{ .Data.data.postgres_pass }}"
RP_AMQP_USER="{{ .Data.data.rabbit_user }}"
RP_AMQP_PASS="{{ .Data.data.rabbit_pass }}"
RP_AMQP_APIUSER="{{ .Data.data.rabbit_user }}"
RP_AMQP_APIPASS="{{ .Data.data.rabbit_pass }}"
RP_INITIAL_ADMIN_PASSWORD="{{ .Data.data.initial_password }}"
{{ end }}
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
        destination = "${NOMAD_SECRETS_DIR}/jobs.env"
        env         = true
      }
      service {
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
          "traefik.http.routers.jobs.service=jobs",
          "traefik.http.services.jobs.loadbalancer.server.port=8686",
          "traefik.http.services.jobs.loadbalancer.server.scheme=http",
          "traefik.expose=true"
        ]
      }
    }
  }
}
