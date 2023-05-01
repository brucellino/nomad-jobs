variable "go_version" {
  type        = string
  description = "Version of Golang used to compile the exporter"
  default     = "1.20.3"
}

variable "go_url" {
  default     = "https://go.dev/dl"
  type        = string
  description = "URL to get go binaries from"
}
variable "exporter_version" {
  type        = string
  description = "Version of the github exporter to use"
  default     = "1.0.3"
}

variable "artifact_url" {
  type        = string
  description = "URL for the artifact -- a GitHub repo"
  default     = "github.com/infinityworks/github-exporter"
}

job "github-exporter" {
  migrate {
    max_parallel     = 1
    health_check     = "checks"
    min_healthy_time = "10s"
    healthy_deadline = "5m"
  }

  group "AAROC" {
    vault {
      policies = ["default"]
    }
    network {
      port "exporter" {}
    }
    update {
      max_parallel      = 2
      health_check      = "checks"
      min_healthy_time  = "10s"
      healthy_deadline  = "5m"
      progress_deadline = "10m"
      auto_revert       = true
      auto_promote      = true
      canary            = 1
      stagger           = "30s"
    }
    task "build" {
      driver = "exec"
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }
      artifact {
        source      = "${var.artifact_url}"
        destination = "${NOMAD_ALLOC_DIR}/gh_exporter"

        options {
          ref = var.exporter_version
          // ref = "master"
          depth = 1
        }
      }
      artifact {
        // source = "${var.go_url}/go${var.go_version}.${attr.kernel.name}-${attr.cpu.arch}.tar.gz"
        source      = "https://go.dev/dl/go1.20.3.linux-arm64.tar.gz"
        destination = "${NOMAD_ALLOC_DIR}/data"
      }
      config {
        command = "bash"
        args    = ["${NOMAD_ALLOC_DIR}/build.sh"]
      }
      template {
        data        = <<EOH
#!/bin/bash
set -eou pipefail
ls -lht ${NOMAD_ALLOC_DIR}/data/
cd ${NOMAD_ALLOC_DIR}/gh_exporter
${NOMAD_ALLOC_DIR}/data/go/bin/go build -buildvcs=false -o ${NOMAD_ALLOC_DIR}/data/github_exporter
        EOH
        destination = "${NOMAD_ALLOC_DIR}/build.sh"
        perms       = "0777"
      }
    }
    task "main" {
      driver = "exec"
      env {
        ORGS              = "brucellino"
        LISTEN_PORT       = "${NOMAD_PORT_exporter}"
        GITHUB_TOKEN_FILE = "${NOMAD_SECRETS_DIR}/gh_token"
      }
      template {
        data        = <<EOH
{{ with secret "kv/data/github" }}{{ .Data.data.exporter_token }}{{ end }}
        EOH
        destination = "${NOMAD_SECRETS_DIR}/gh_token"
      }
      config {
        command = "${NOMAD_ALLOC_DIR}/data/github_exporter"
      }
      service {
        port = "exporter"
        check {
          type     = "http"
          port     = "exporter"
          path     = "/health"
          interval = "10s"
          timeout  = "5s"
        }
      }
    }
  }

  group "hah" {
    vault {
      policies = ["default"]
    }
    network {
      port "exporter" {}
    }
    update {
      max_parallel      = 2
      health_check      = "checks"
      min_healthy_time  = "10s"
      healthy_deadline  = "5m"
      progress_deadline = "10m"
      auto_revert       = true
      auto_promote      = true
      canary            = 1
      stagger           = "30s"
    }
    task "build" {
      driver = "exec"
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }
      artifact {
        source      = "${var.artifact_url}"
        destination = "${NOMAD_ALLOC_DIR}/gh_exporter"

        options {
          ref = var.exporter_version
          // ref = "master"
          depth = 1
        }
      }
      artifact {
        // source = "${var.go_url}/go${var.go_version}.${attr.kernel.name}-${attr.cpu.arch}.tar.gz"
        source      = "https://go.dev/dl/go1.20.3.linux-arm64.tar.gz"
        destination = "${NOMAD_ALLOC_DIR}/data"
      }
      config {
        command = "bash"
        args    = ["${NOMAD_ALLOC_DIR}/build.sh"]
      }
      template {
        data        = <<EOH
#!/bin/bash
set -eou pipefail
ls -lht ${NOMAD_ALLOC_DIR}/data/
cd ${NOMAD_ALLOC_DIR}/gh_exporter
${NOMAD_ALLOC_DIR}/data/go/bin/go build -buildvcs=false -o ${NOMAD_ALLOC_DIR}/data/github_exporter
        EOH
        destination = "${NOMAD_ALLOC_DIR}/build.sh"
        perms       = "0777"
      }
    }

    task "main" {
      driver = "exec"
      env {
        ORGS              = "hashi-at-home"
        LISTEN_PORT       = "${NOMAD_PORT_exporter}"
        GITHUB_TOKEN_FILE = "${NOMAD_SECRETS_DIR}/gh_token"
      }
      template {
        data        = <<EOH
{{ with secret "kv/data/github" }}{{ .Data.data.exporter_token }}{{ end }}
        EOH
        destination = "${NOMAD_SECRETS_DIR}/gh_token"
      }
      config {
        command = "${NOMAD_ALLOC_DIR}/data/github_exporter"
      }
      service {
        port = "exporter"
        check {
          type     = "http"
          port     = "exporter"
          path     = "/health"
          interval = "10s"
          timeout  = "5s"
        }
      }
    }
  }

  group "personal" {
    vault {
      policies = ["default"]
    }
    network {
      port "exporter" {}
    }
    update {
      max_parallel      = 2
      health_check      = "checks"
      min_healthy_time  = "10s"
      healthy_deadline  = "5m"
      progress_deadline = "10m"
      auto_revert       = true
      auto_promote      = true
      canary            = 1
      stagger           = "30s"
    }
    task "build" {
      driver = "exec"
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }
      artifact {
        source      = "${var.artifact_url}"
        destination = "${NOMAD_ALLOC_DIR}/gh_exporter"

        options {
          ref = var.exporter_version
          // ref = "master"
          depth = 1
        }
      }
      artifact {
        // source = "${var.go_url}/go${var.go_version}.${attr.kernel.name}-${attr.cpu.arch}.tar.gz"
        source      = "https://go.dev/dl/go1.20.3.linux-arm64.tar.gz"
        destination = "${NOMAD_ALLOC_DIR}/data"
      }
      config {
        command = "bash"
        args    = ["${NOMAD_ALLOC_DIR}/build.sh"]
      }
      template {
        data        = <<EOH
#!/bin/bash
set -eou pipefail
ls -lht ${NOMAD_ALLOC_DIR}/data/
cd ${NOMAD_ALLOC_DIR}/gh_exporter
${NOMAD_ALLOC_DIR}/data/go/bin/go build -buildvcs=false -o ${NOMAD_ALLOC_DIR}/data/github_exporter
        EOH
        destination = "${NOMAD_ALLOC_DIR}/build.sh"
        perms       = "0777"
      }
    }
    task "main" {
      driver = "exec"
      env {
        USERS              = "AAROC"
        LISTEN_PORT       = "${NOMAD_PORT_exporter}"
        GITHUB_TOKEN_FILE = "${NOMAD_SECRETS_DIR}/gh_token"
      }
      template {
        data        = <<EOH
{{ with secret "kv/data/github" }}{{ .Data.data.exporter_token }}{{ end }}
        EOH
        destination = "${NOMAD_SECRETS_DIR}/gh_token"
      }
      config {
        command = "${NOMAD_ALLOC_DIR}/data/github_exporter"
      }
      service {
        port = "exporter"
        check {
          type     = "http"
          port     = "exporter"
          path     = "/health"
          interval = "10s"
          timeout  = "5s"
        }
      }
    }
  }
}
