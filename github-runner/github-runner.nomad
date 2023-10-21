variable "runner_version" {
  description = "Version to use for the github runner.\nSee https://github.com/actions/runner/releases/"
  default = "2.310.2"
  type = string
}

variable "github_org" {
  description = "Name of the github org we attach the runner to"
  default = "SouthAfricaDigitalScience"
  type = string
}

variable "token" {
  description = "Github Personal Access Token"
  default = "AAQEOZFGCRNN2DT7DBTYXMTEGKUB2"
  type = string
}
job "github-runner" {
  datacenters = ["dc1"]
  group "main" {
    task "configure" {
      driver = "exec"
      artifact {
        source = "https://github.com/actions/runner/releases/download/v${var.runner_version}/actions-runner-linux-${attr.cpu.arch}-${var.runner_version}.tar.gz"
      }
      lifecycle {
        hook = "prestart"
        sidecar = false
      }
      config {
        command = "/bin/bash"
        args = [
          "local/config.sh",
          "--unattended",
          "--url https://github.com/${var.github_org}",
          "--token  ${var.token}",
          "--labels test"
        ]
      }
    }
    task "run" {
      env {
        RUNNER_CFG_PAT = var.token
      }
      driver = "exec"
      config {
        command = "/bin/bash"
        args = [
          "local/run.sh"
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
          var.token
        ]
      }
    }
  }
}
