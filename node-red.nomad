job "nodered" {
  datacenters = ["dc1"]
  update {
    max_parallel = 2
    health_check = "checks"
    canary = 1
    auto_promote = true
    auto_revert = true
  }
  group "automation" {
    count = 1

    network {
      port "ui" {
        static = 1880
      }
    }

    service {
      tags = ["automation", "nodered"]
      port = "ui"

      check {
        type     = "http"
        port     = "ui"
        path     = "/"
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
        cpu  = 1000
        memory = 256
        memory_max = 512
      }
    } // install task

    task "nodered" {
      driver = "raw_exec"
      env {
        XDG_CONFIG_HOME = "${NOMAD_ALLOC_DIR}"
      }
      template {
        destination = "run.sh"
        data = <<EOT
#!/bin/bash
source ${XDG_CONFIG_HOME}/nvm/nvm.sh
nvm use 16
node-red-pi --max-old-space-size=256
EOT
        perms = "0755"
      }
      config {
        command = "/bin/bash"
        args = ["run.sh"]
      }

      resources {
        cores = 2
        memory = 1024
        memory_max = 2048
      }
    }
  }
}
