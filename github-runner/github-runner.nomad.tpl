job "github-runner-${org}" {

  name = "github-runner-${org}"

  datacenters = ["dc1"]
  migrate {
    max_parallel     = 2
    health_check     = "task_states"
    min_healthy_time = "30s"
    healthy_deadline = "5m"
  }
  update {
    max_parallel      = 3
    health_check      = "task_states"
    min_healthy_time  = "30s"
    healthy_deadline  = "5m"
    progress_deadline = "10m"
    auto_revert       = true
    auto_promote      = true
    canary            = 1
    stagger           = "30s"
  }
  reschedule {
    interval       = "1h"
    delay          = "30s"
    delay_function = "exponential"
    max_delay      = "120s"
    unlimited      = true
  }

  group "${org}" {

    task "configure" {
      env {
        RUNNER_CFG_PAT = "${registration_token}"
      }
      lifecycle {
        hook = "prestart"
      }
      driver = "exec"
      artifact {
        source = "https://github.com/actions/runner/releases/download/v${runner_version}/actions-runner-linux-$${attr.cpu.arch}-${runner_version}.tar.gz"
        destination = "$${NOMAD_ALLOC_DIR}/actions-runner"
        mode = "dir"
      }
      config {
        command = "$${NOMAD_ALLOC_DIR}/actions-runner/config.sh"
        args = [
          "--unattended",
          "--url", "https://github.com/${org}",
          "--token", "${registration_token}",
          "--labels", "hah",
          "--ephemeral"
        ]
      }
    }

    task "launch" {
      driver = "exec"
      config {
        command = "$${NOMAD_ALLOC_DIR}/actions-runner/run.sh"
      }

      service {
        name = "github-runner-${org}"
        tags = ["github-runner-${org}"]
        provider = "consul"
        check {
          interval = "15s"
          timeout = "10s"
          type = "script"
          command = "$${NOMAD_ALLOC_DIR}/actions-runner/run.sh"
          args = ["--check", "--url", "https://github.com/${org}", "--pat", "${check_token}" ]
        }
      }

      scaling "cpu" {
        enabled = true
        min     = 100
        max     = 150

        policy {
          cooldown = "5m"
          evaluation_interval = "10s"
          strategy "target-value" {
            target = 2
          }
        }
      }
    }

    task "remove" {
      lifecycle {
        hook = "poststop"
        sidecar = false
      }
      driver = "exec"
      config {
        command = "$${NOMAD_ALLOC_DIR}/actions-runner/config.sh"
        args = [
          "remove",
          "--token",
          "${registration_token}"
        ]
      }
    } // remove task
  } // task group
}
