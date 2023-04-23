job "nodered" {
  datacenters = ["dc1"]
  meta {
    auto-backup = true
    backup-schedule = "@daily"
    backup-target-db = "postgres"
  }
  update {
    max_parallel = 1
    health_check = "checks"
    canary = 1
    auto_promote = true
    auto_revert = true
  }
  group "automation" {
    count = 1
    constraint {
      attribute = "${attr.unique.consul.name}"
      operator = "=="
      value = "sense"
    }
    network {
      port "ui" {}
    }

    service {
      tags = ["automation", "nodered", "urlprefix-/nodered"]
      port = "ui"

      check {
        type     = "http"
        port     = "ui"
        path     = "/nodered/"
        interval = "10s"
        timeout  = "5s"
      }

      check_restart {
        grace = "600s"
        limit = 2
      }
    }

    task "install" {
      driver = "raw_exec"
      lifecycle {
        hook = "prestart"
      }
      env {
        XDG_CONFIG_HOME = "${NOMAD_ALLOC_DIR}"
      }
      template {
        data = <<EOT
#!/bin/bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
echo ${XDG_CONFIG_HOME}
pwd
ls -lht
source ${XDG_CONFIG_HOME}/nvm/nvm.sh
nvm install --lts 16
nvm use 16
npm install -g --unsafe-perm node-red
EOT
        destination = "install.sh"
        perms = "0755"
      }
      config {
        command = "/bin/bash"
        args = ["install.sh"]
      }

      resources {
        cpu  = 250
        memory = 256
        // memory_max = 512
      }
    } // install task

    task "nodered" {
      driver = "exec"
      env {
        XDG_CONFIG_HOME = "${NOMAD_ALLOC_DIR}"
        PORT = "${NOMAD_PORT_ui}"
      }
      template {
        destination = "run.sh"
        data = <<EOT
#!/bin/bash
source ${XDG_CONFIG_HOME}/nvm/nvm.sh
nvm use 16
node-red-pi --max-old-space-size=256 --settings settings.js
EOT
        perms = "0755"
      }

      template {
        destination = "settings.js"
        data = <<EOT
module.exports = {
  uiPort: process.env.PORT || 1880,
  httpAdminRoot: "/nodered",
  httpStatic: '/nodered/node-red-static',
  logging: {
    console: {
      level: "warn",
      metrics: false,
      audit: false,
    }
  },
  editorTheme: {
    page: {
      title: "${NOMAD_TASK_NAME} (${NOMAD_JOB_ID})"
    },
    theme: "solarized-dark",
    codeEditor: {
      lib: "monaco",
      options: {
        theme: "github",
        fontSize: 20,
        fontFamily: "Cascadia Code, Fira Code, Consolas, 'Courier New', monospace",
        fontLigatures: true,
      }
    }
  }
}
EOT
      }
      config {
        command = "/bin/bash"
        args = ["run.sh"]
      }

      resources {
        cores = 1
        memory = 1024
        // memory_max = 2048
      }
    }
  }
}
