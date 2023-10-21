variable "runner_version" {
  description = "Version to use for the github runner.\nSee https://github.com/actions/runner/releases/"
  default = "2.303.0"
  type = string
}

// variable "github_org" {
//   description = "Name of the github org we attach the runner to"
//   default = "SouthAfricaDigitalScience"
//   type = string
// }
job "github-runner" {
  datacenters = ["dc1"]
  group "main" {
    task "dependencies" {
      driver = "exec"
      artifact {
        source = "https://github.com/actions/runner/releases/download/v${runner_version}/actions-runner-linux-arm64-${runner_version}.tar.gz"
      }
      config {
        command = "./bin/installdependencies.sh"
        args = []
      }
    }
    task "launch" {
      env {
        RUNNER_CFG_PAT = "${token}"
      }
      driver = "exec"
      artifact {
        source = "https://github.com/actions/runner/releases/download/v${runner_version}/actions-runner-linux-arm64-${runner_version}.tar.gz"
      }
      config {
        command = "config.sh"
        args = [
          "config.sh",
          "--unattended",
          "--url", "https://github.com/${org_name}",
          "--token", "${token}",
          "--labels", "test"
        ]
      }
    }
    task "remove" {
      lifecycle {
        hook = "poststop"
        sidecar = false
      }
      driver = "exec"
      config {
        command = "config.sh"
        args = [
          "remove",
          "--token",
          "${token}"
        ]
      }
    }
  }
}
