# There can only be a single job definition per file. This job is named
# "example" so it will create a job with the ID and Name "example".

# The "job" stanza is the top-most configuration option in the job
# specification. A job is a declarative specification of tasks that Nomad
# should run. Jobs have a globally unique name, one or many task groups, which
# are themselves collections of one or many tasks.
#
# For more information and examples on the "job" stanza, please see
# the online documentation at:
#
#     https://www.nomadproject.io/docs/job-specification/job
#
job "promtail" {

  meta {
    auto-backup = true
    backup-schedule = "@daily"
    backup-target-db = "postgres"
  }
  datacenters = ["dc1"]
  type = "system"

  constraint {
    attribute = "${node.class}"
    operator = "regexp"
    value = "64"
  }

  group "promtail" {
    count = 1

    network {
      port "http" {
        static = 9080
      }
    }

    service {
      name = "promtail"
      tags = ["logs", "promtail", "observability"]
      port = "http"

      check {
        name     = "promtail-alive"
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
      }

    }

    restart {
      attempts = 3
      interval = "10m"
      delay = "15s"
      mode = "delay"
    }

    ephemeral_disk {
      size = 300
    }

    task "promtail" {
      # The "driver" parameter specifies the task driver that should be used to
      # run the task.
      driver = "raw_exec"

      config {
        command = "promtail"
        args = ["-config.file=local/promtail.yml"]
      }

      // artifact {
      //    source = "http://minio-api.service.consul:9000/loki-bin/promtail-linux-${attr.cpu.arch}.zip"
      //    destination = "local/promtail"
      //    mode = "file"
      // }
      artifact {
        source = "https://github.com/grafana/loki/releases/download/v2.5.0/promtail-linux-arm64.zip"
        destination = "local/promtail"
        mode = "file"
      }


      resources {
        cpu    = 60 # 500 MHz
        memory = 125 # 256MB
      }


      template {
         data          = file("promtail.yml.tpl")
         destination   = "local/promtail.yml"
         change_mode   = "signal"
         change_signal = "SIGHUP"
      }
    }
  }
}
