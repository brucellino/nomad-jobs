job "dashboard" {
  datacenters = ["dc1"]

  type = "service"

  # Select ARMv7 machines
  constraint {
    attribute = "${attr.cpu.arch}"
    operator  = "="
    value     = "arm"
  }

  # select machines with more than 4GB of RAM
  constraint {
    attribute = "${attr.memory.totalbytes}"
    value     = "2GB"
    operator  = ">"
  }

  constraint {
    attribute = "${node.class}"
    value     = "32"
  }

  update {
    max_parallel      = 1
    min_healthy_time  = "20s"
    healthy_deadline  = "7m"
    progress_deadline = "15m"
    auto_revert       = true
    canary            = 1
  }

  migrate {
    max_parallel = 2

    # Specifies the mechanism in which allocations health is determined. The
    # potential values are "checks" or "task_states".
    health_check = "checks"

    # Specifies the minimum time the allocation must be in the healthy state
    # before it is marked as healthy and unblocks further allocations from being
    # migrated. This is specified using a label suffix like "30s" or "15m".
    min_healthy_time = "15s"

    # Specifies the deadline in which the allocation must be marked as healthy
    # after which the allocation is automatically transitioned to unhealthy. This
    # is specified using a label suffix like "2m" or "1h".
    healthy_deadline = "5m"
  }

  group "server" {
    count = 1

    network {
      port "grafana_server" {
        to = 3000
      }
    }

    service {
      name = "grafana"
      tags = ["monitoring", "dashboard"]
      port = "grafana_server"

      # The "check" stanza instructs Nomad to create a Consul health check for
      # this service. A sample check is provided here for your convenience;
      # uncomment it to enable it. The "check" stanza is documented in the
      # "service" stanza documentation.

      check {
        name     = "api"
        path     = "/api/health"
        type     = "tcp"
        interval = "20s"
        timeout  = "5s"
      }
    }

    restart {
      # The number of attempts to run the job within the specified interval.
      attempts = 2
      interval = "10m"

      # The "delay" parameter specifies the duration to wait before restarting
      # a task after it has failed.
      delay = "15s"

      # The "mode" parameter controls what happens when a task has restarted
      # "attempts" times within the interval. "delay" mode delays the next
      # restart until the next interval. "fail" mode does not restart the task
      # if "attempts" has been hit within the interval.
      mode = "fail"
    }

    # The "ephemeral_disk" stanza instructs Nomad to utilize an ephemeral disk
    # instead of a hard disk requirement. Clients using this stanza should
    # not specify disk requirements in the resources stanza of the task. All
    # tasks in this group will share the same ephemeral disk.
    #
    # For more information and examples on the "ephemeral_disk" stanza, please
    # see the online documentation at:
    #
    #     https://www.nomadproject.io/docs/job-specification/ephemeral_disk
    #
    ephemeral_disk {
      # When sticky is true and the task group is updated, the scheduler
      # will prefer to place the updated allocation on the same node and
      # will migrate the data. This is useful for tasks that store data
      # that should persist across allocation updates.
      # sticky = true
      #
      # Setting migrate to true results in the allocation directory of a
      # sticky allocation directory to be migrated.
      # migrate = true
      #
      # The "size" parameter specifies the size in MB of shared ephemeral disk
      # between tasks in the group.
      size = 300
    }

    affinity {
      attribute = "${node.datacenter}"
      value     = "dc1"
      weight    = 100
    }

    # The "spread" stanza allows operators to increase the failure tolerance of
    # their applications by specifying a node attribute that allocations
    # should be spread over.
    #
    # For more information and examples on the "spread" stanza, please
    # see the online documentation at:
    #
    #     https://www.nomadproject.io/docs/job-specification/spread
    #
    # spread {
    # attribute specifies the name of a node attribute or metadata
    # attribute = "${node.datacenter}"


    # targets can be used to define desired percentages of allocations
    # for each targeted attribute value.
    #
    #   target "us-east1" {
    #     percent = 60
    #   }
    #   target "us-west1" {
    #     percent = 40
    #   }
    #  }

    # The "task" stanza creates an individual unit of work, such as a Docker
    # container, web application, or batch processing.
    #
    # For more information and examples on the "task" stanza, please see
    # the online documentation at:
    #
    #     https://www.nomadproject.io/docs/job-specification/task
    #
    task "grafana" {
      # The "driver" parameter specifies the task driver that should be used to
      # run the task.
      driver = "raw_exec"

      artifact {
        source = "https://dl.grafana.com/oss/release/grafana-8.3.3.linux-armv7.tar.gz"

        options {
          checksum = "sha256:9abddf9be0b5c4e7086676a1de5289fd4fc08faec3c27b653811535c4f0fc9fa"
        }
      }

      logs {
        max_files     = 10
        max_file_size = 15
      }

      resources {
        cpu    = 1500
        memory = 2048
      }

      config {
        command = "local/grafana-8.3.3/bin/grafana-server"
        args    = ["-homepath=local/grafana-8.3.3", "--config=local/conf.ini"]
      }

      template {
        data = <<EOT
[paths]
data = local/data/
logs = local/log/
plugins = local/plugins
[analytics]
reporting_enabled = false
[snapshots]
external_enabled = false
EOT

        destination = "local/conf.ini"
      }
    }
  }
}
