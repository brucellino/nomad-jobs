job "clickstack" {
  group "clickhouse" {
    network {
      port "http" {
        to = 8123
      }
      port "native" {
        to = 9000
      }
      port "mongo" {
        to = 27017
      }
      port "otel-col-health" {
        to = 13133
      }
      port "otel-col-http" {
        to = 4318
      }
      port "otel-col-metrics" {
        to = 8888
      }
      port "opamp-api" {
        to = 8080
      }
      port "opamp-app" {
        to = 8080
      }
    }
    service {
      name = "clickstack-clickhouse-http"
      port = "http"
      check {
        type     = "http"
        path     = "/ping"
        interval = "20s"
        timeout  = "5s"
      }
    }

    service {
      port = "mongo"
      name = "clickstack-mongo"
      check {
        type     = "tcp"
        port     = "mongo"
        interval = "10s"
        timeout  = "5s"
      }
      # check {
      #   type = "script"
      #   command = "mongo"
      #   args = ["--eval", "'db.runCommand('ping').ok'"]
      #   interval = "10s"
      #   timeout = "5s"
      #   task = "mongo"
      # }
    }

    service {
      port = "otel-col-health"
      name = "otel-collector-health"
      check {
        type     = "http"
        path     = "/"
        port     = "otel-col-health"
        interval = "20s"
        timeout  = "5s"
      }
    }


    task "mongo" {
      driver = "docker"
      config {
        image = "mongo:5.0.14-focal"
        ports = ["mongo"]
      }
    }

    task "ch" {
      constraint {
        attribute = "${attr.unique.hostname}"
        operator  = "regexp"
        value     = "ticklish|cape"
      }
      driver = "docker"
      config {
        image = "clickhouse/clickhouse-server:25.6-alpine"
        ports = ["http", "native"]
      }
      env {
        CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT = 1
      }
      resources {
        cpu    = 4096
        memory = 2048
      }
    }

    task "otel-collector" {
      driver = "docker"
      resources {
        cpu    = 500
        memory = 512
      }
      config {
        image = "docker.hyperdx.io/hyperdx/hyperdx-otel-collector:2"
      }
      env {
        CLICKHOUSE_ENDPOINT                       = "http://${NOMAD_ADDR_http}?dial_timeout=10s"
        HYPERDX_OTEL_EXPORTER_CLICKHOUSE_DATABASE = "default"
        HYPERDX_LOG_LEVEL                         = "debug"
        OPAMP_SERVER_URL                          = "http://${NOMAD_ADDR_opamp-api}"
      }
    }

    task "hyperdx" {
      resources {
        cpu    = 1000
        memory = 1024
      }
      driver = "docker"
      config {
        image = "docker.hyperdx.io/hyperdx/hyperdx"
        ports = ["opamp-api", "opamp-app"]
      }
      env {
        FRONTEND_URL                = "http://${NOMAD_ADDR_opamp-api}"
        HYPERDX_API_KEY             = "xyz"
        HYPERDX_API_PORT            = "${NOMAD_PORT_opamp-api}"
        HYPERDX_APP_PORT            = "${NOMAD_PORT_opamp-app}"
        HYPERDX_APP_URL             = "http://${NOMAD_IP_opamp-api}"
        HYPERDX_LOG_LEVEL           = "debug"
        MINER_API_URL               = "http://miner:5123"
        MONGO_URI                   = "mongodb://${NOMAD_ADDR_mongo}/hyperdx"
        SERVER_URL                  = "http://127.0.0.1:${NOMAD_PORT_opamp-api}"
        OPAMP_PORT                  = "${NOMAD_PORT_opamp-api}"
        OTEL_EXPORTER_OTLP_ENDPOINT = "http://${NOMAD_ADDR_otel-col-http}"
        OTEL_SERVICE_NAME           = "hdx-oss-app"
        USAGE_STATS_ENABLED         = true
        DEFAULT_CONNECTIONS         = "[{\"name\":\"Local ClickHouse\",\"host\":\"http://${NOMAD_ADDR_http}\",\"username\":\"default\",\"password\":\"\"}]"
        DEFAULT_SOURCES             = "[{\"from\":{\"databaseName\":\"default\",\"tableName\":\"otel_logs\"},\"kind\":\"log\",\"timestampValueExpression\":\"TimestampTime\",\"name\":\"Logs\",\"displayedTimestampValueExpression\":\"Timestamp\",\"implicitColumnExpression\":\"Body\",\"serviceNameExpression\":\"ServiceName\",\"bodyExpression\":\"Body\",\"eventAttributesExpression\":\"LogAttributes\",\"resourceAttributesExpression\":\"ResourceAttributes\",\"defaultTableSelectExpression\":\"Timestamp,ServiceName,SeverityText,Body\",\"severityTextExpression\":\"SeverityText\",\"traceIdExpression\":\"TraceId\",\"spanIdExpression\":\"SpanId\",\"connection\":\"Local ClickHouse\",\"traceSourceId\":\"Traces\",\"sessionSourceId\":\"Sessions\",\"metricSourceId\":\"Metrics\"},{\"from\":{\"databaseName\":\"default\",\"tableName\":\"otel_traces\"},\"kind\":\"trace\",\"timestampValueExpression\":\"Timestamp\",\"name\":\"Traces\",\"displayedTimestampValueExpression\":\"Timestamp\",\"implicitColumnExpression\":\"SpanName\",\"serviceNameExpression\":\"ServiceName\",\"bodyExpression\":\"SpanName\",\"eventAttributesExpression\":\"SpanAttributes\",\"resourceAttributesExpression\":\"ResourceAttributes\",\"defaultTableSelectExpression\":\"Timestamp,ServiceName,StatusCode,round(Duration/1e6),SpanName\",\"traceIdExpression\":\"TraceId\",\"spanIdExpression\":\"SpanId\",\"durationExpression\":\"Duration\",\"durationPrecision\":9,\"parentSpanIdExpression\":\"ParentSpanId\",\"spanNameExpression\":\"SpanName\",\"spanKindExpression\":\"SpanKind\",\"statusCodeExpression\":\"StatusCode\",\"statusMessageExpression\":\"StatusMessage\",\"connection\":\"Local ClickHouse\",\"logSourceId\":\"Logs\",\"sessionSourceId\":\"Sessions\",\"metricSourceId\":\"Metrics\"},{\"from\":{\"databaseName\":\"default\",\"tableName\":\"\"},\"kind\":\"metric\",\"timestampValueExpression\":\"TimeUnix\",\"name\":\"Metrics\",\"resourceAttributesExpression\":\"ResourceAttributes\",\"metricTables\":{\"gauge\":\"otel_metrics_gauge\",\"histogram\":\"otel_metrics_histogram\",\"sum\":\"otel_metrics_sum\",\"_id\":\"682586a8b1f81924e628e808\",\"id\":\"682586a8b1f81924e628e808\"},\"connection\":\"Local ClickHouse\",\"logSourceId\":\"Logs\",\"traceSourceId\":\"Traces\",\"sessionSourceId\":\"Sessions\"},{\"from\":{\"databaseName\":\"default\",\"tableName\":\"hyperdx_sessions\"},\"kind\":\"session\",\"timestampValueExpression\":\"TimestampTime\",\"name\":\"Sessions\",\"displayedTimestampValueExpression\":\"Timestamp\",\"implicitColumnExpression\":\"Body\",\"serviceNameExpression\":\"ServiceName\",\"bodyExpression\":\"Body\",\"eventAttributesExpression\":\"LogAttributes\",\"resourceAttributesExpression\":\"ResourceAttributes\",\"defaultTableSelectExpression\":\"Timestamp,ServiceName,SeverityText,Body\",\"severityTextExpression\":\"SeverityText\",\"traceIdExpression\":\"TraceId\",\"spanIdExpression\":\"SpanId\",\"connection\":\"Local ClickHouse\",\"logSourceId\":\"Logs\",\"traceSourceId\":\"Traces\",\"metricSourceId\":\"Metrics\"}]"
      }
    }
  }
}
