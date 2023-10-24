job "github-runner-${org}" {
  name = "github-runner-${org}"
  datacenters = ["dc1"]
  group "${org}" {

    task "configure" {
      env {
        RUNNER_CFG_PAT = "${token}"
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
          "config.sh",
          "--unattended",
          "--url", "https://github.com/${org}",
          "--token", "${token}",
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
          "${token}"
        ]
      }
    } // remove task
  } // task group
}
