// The batch job that takes a snapshot of the Nomad cluster's state
// and backs it up
variable "version" {
  type    = string
  default = "2.0.3"
}
job "state-snapshot" {
  ui {
    description = "Nomad state snapshot batch job."
    link {
      label = "Source"
      url   = "https://github.com/hashi-at-home/nomad-backup-operator"
    }

    link {
      label = "Docs"
      url   = "https://github.com/hashi-at-home/nomad-backup-operator"
    }
  }

  meta {
    source = "https://github.com/hashi-at-home/nomad-backup-operator"
    docs   = "https://github.com/hashi-at-home/nomad-backup-operator"
    owner  = "brucellino"
    scope  = "platform"
  }
  type = "batch"
  periodic {
    crons = ["@daily"]
  }

  group "nomad" {
    ephemeral_disk {
      migrate = false
      size    = 250
      sticky  = false
    }
    task "main" {
      logs {
        max_files     = 1
        max_file_size = 100
        disabled      = false
      }
      resources {
        cpu    = 100
        memory = 25
      }
      vault {}
      // We need the application from the releases in the github repo.
      artifact {
        source      = "https://github.com/hashi-at-home/nomad-backup-operator/releases/download/v${var.version}/nomad-operator-linux-arm64"
        destination = "local/backup"
        mode        = "file"
      }
      // Get a nomad token and pass it to the environment
      template {
        data        = <<EOT
{{ with secret "nomad/creds/management" }}
DATA={{ .Data }}
NOMAD_TOKEN={{ .Data.secret_id }}
{{ end }}
        EOT
        destination = "nomad.env"
        env         = true
      }
      driver = "exec"
      config {
        command = "local/backup"
      }
    }
  }
}
