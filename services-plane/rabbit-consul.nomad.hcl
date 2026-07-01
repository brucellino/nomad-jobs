job "rabbitmq" {
  region      = "global"
  datacenters = ["dc1"]
  type        = "service"

  affinity {
    attribute = "${attr.cpu.usablecompute}"
    operator  = ">="
    value     = "6000"
    weight    = 50
  }

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  constraint {
    attribute = "${attr.cpu.arch}"
    operator  = "regexp"
    value     = "(amd64|arm64)"
  }

  # Spread instances across different nodes for HA
  constraint {
    operator = "distinct_hosts"
    value    = "true"
  }

  group "consul-cluster" {
    count = 2

    network {
      port "amqp" {
        to = 5672
      }
      port "management" {
        to = 15672
      }
      port "metrics" {
        to = 15692
      }
      port "clustering" {
        static = 25672
        to     = 25672
      }
      port "epmd" {
        static = 4369
        to     = 4369
      }
    }

    task "server" {
      driver = "docker"

      config {
        image    = "rabbitmq:4.3-management-alpine"
        ports    = ["amqp", "management", "metrics", "clustering", "epmd"]
        hostname = "rabbitmq-${NOMAD_ALLOC_INDEX}"
      }

      env {
        RABBITMQ_DEFAULT_USER         = "admin"
        RABBITMQ_DEFAULT_PASS         = "changeme"
        RABBITMQ_ERLANG_COOKIE        = "rabbitmq-cookie-secret-cluster"
        RABBITMQ_NODENAME             = "rabbit@${NOMAD_IP_clustering}"
        RABBITMQ_USE_LONGNAME         = "true"
        ERL_EPMD_PORT                 = "4369"
        RABBITMQ_DIST_PORT            = "25672"
        RABBITMQ_CONFIG_FILE          = "local/rabbitmq.conf"
        RABBITMQ_ENABLED_PLUGINS_FILE = "local/enabled_plugins"
        HOME                          = "${NOMAD_TASK_DIR}"
      }
      template {
        data        = "{{ env \"RABBITMQ_ERLANG_COOKIE\" }}"
        destination = "local/.erlang.cookie"
        perms       = "0400"
      }


      # RabbitMQ configuration with Consul peer discovery
      template {
        data        = <<EOF
# Clustering configuration
cluster_formation.peer_discovery_backend = rabbit_peer_discovery_consul
# Set Docker bridge address as consul http address
cluster_formation.consul.host = 172.17.0.1
cluster_formation.consul.port = 8500
cluster_formation.consul.scheme = http
cluster_formation.consul.svc = rabbitmq-cluster
cluster_formation.consul.svc_addr_auto = false
cluster_formation.consul.svc_addr = {{ env "NOMAD_IP_clustering" }}
cluster_formation.consul.svc_port = {{ env "NOMAD_PORT_clustering" }}
cluster_formation.consul.include_nodes_with_warnings = false

# Cluster formation settings
cluster_formation.node_cleanup.only_log_warning = true
cluster_formation.node_cleanup.interval = 60
#cluster_formation.randomized_startup_delay_range.min = 5
#cluster_formation.randomized_startup_delay_range.max = 30

# Management and metrics
management.tcp.port = 15672
prometheus.tcp.port = 15692

# Networking
listeners.tcp.default = 5672
# distribution.buffer_size = 128MB

# Logging
log.console = true
log.console.level = info
log.file.level = info

# Performance tuning
vm_memory_high_watermark.relative = 0.6
disk_free_limit.absolute = 2GB
EOF
        destination = "local/rabbitmq.conf"
        change_mode = "restart"
      }

      # Enable required plugins
      template {
        data        = <<EOF
[rabbitmq_management,rabbitmq_prometheus,rabbitmq_peer_discovery_consul].
EOF
        destination = "local/enabled_plugins"
        change_mode = "restart"
      }

      resources {
        cpu    = 1000
        memory = 1024
      }

      # AMQP service
      service {
        name = "rabbitmq-amqp"
        port = "amqp"
        tags = ["amqp", "message-bus"]

        check {
          type     = "tcp"
          interval = "30s"
          timeout  = "5s"
        }

        check {
          name     = "rabbitmq-node-health"
          type     = "script"
          command  = "/bin/sh"
          args     = ["-c", "rabbitmqctl node_health_check"]
          interval = "60s"
          timeout  = "10s"
        }
      }

      # Management UI service
      service {
        name = "rabbitmq-management"
        port = "management"
        tags = ["management", "ui"]

        # check {
        #   type     = "http"
        #   path     = "/api/health/checks/virtual-hosts"
        #   interval = "30s"
        #   timeout  = "5s"
        # }
      }

      # Metrics service
      service {
        name = "rabbitmq-metrics"
        port = "metrics"
        tags = ["metrics", "prometheus"]

        check {
          type     = "http"
          path     = "/metrics"
          interval = "30s"
          timeout  = "5s"
        }
      }

      kill_timeout = "60s"

      logs {
        max_files     = 5
        max_file_size = 15
      }
    }

    # Restart policy for resilience
    restart {
      attempts = 3
      delay    = "30s"
      interval = "5m"
      mode     = "fail"
    }

    # Reschedule failed allocations
    reschedule {
      delay          = "30s"
      delay_function = "exponential"
      max_delay      = "10m"
      unlimited      = true
    }
  }

  update {
    max_parallel      = 1
    min_healthy_time  = "120s"
    healthy_deadline  = "10m"
    progress_deadline = "15m"
    auto_revert       = true
    canary            = 0
  }

  migrate {
    max_parallel     = 1
    health_check     = "checks"
    min_healthy_time = "120s"
    healthy_deadline = "10m"
  }
}
