variable "jenkins_war" {
  type = map(string)
  default = {
    war_version = "2.426.2"
    war_sha256  = "3731b9f44973fbbf3e535f98a80c21aad9719cb4eea8a1e59e974c11fe846848" #pragma: allowlist secret
  }
  description = "Version of the Jenkins release to deploy"
}

variable "plugin_manager" {
  type = map(string)
  default = {
    version = "2.12.8"
  }
  description = "Map of configuration entries for the java plugin manager."
}

job "jenkins" {

  update {
    max_parallel = 1
    health_check = "checks"
    auto_revert  = true
    auto_promote = true
    canary       = 1
  }

  datacenters = ["dc1"]

  type = "service"

  group "controller" {
    count = 1
    network {
      port "ui" {}
      // mode = "host"
      port "agent" {}
    }

    volume "casc" {
      type      = "host"
      read_only = false
      source    = "jenkins_casc"
    }

    task "plugins" {
      driver = "exec"
      env {
        CASC_JENKINS_CONFIG = "alloc/data/jenkins.yml"
        JENKINS_HOME        = "alloc/jenkins"
        CACHE_DIR           = "local/"
      }
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }
      volume_mount {
        volume      = "casc"
        destination = "/usr/share/jenkins/"
        read_only   = false
      }

      artifact {
        source      = "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/${var.plugin_manager.version}/jenkins-plugin-manager-${var.plugin_manager.version}.jar"
        destination = "alloc/data/jenkins-plugin-manager.jar"
        mode        = "file"
      }

      artifact {
        source      = "https://get.jenkins.io/war-stable/${var.jenkins_war.war_version}/jenkins.war"
        destination = "alloc/data/jenkins.war"
        mode        = "file"
        options {
          checksum = "sha256:${var.jenkins_war.war_sha256}"
        }
      }

      template {
        data        = "{{ key \"nomad/jenkins/plugins\" }}"
        destination = "alloc/data/plugins.txt"
        change_mode = "restart"
      }

      template {
        data        = <<EOF
#!/bin/bash
set -eou pipefail
mkdir -vp /alloc/jenkins/plugins
java -jar alloc/data/jenkins-plugin-manager.jar \
     --war alloc/data/jenkins.war \
     --plugin-file alloc/data/plugins.txt \
     --skip-failed-plugins \
     --verbose \
     -d /alloc/jenkins/plugins/
ls -lht /alloc/jenkins/plugins
echo "plugins installed"
EOF
        destination = "local/plugins.sh"
        perms       = "0777"
      }

      config {
        command = "/bin/bash"
        args    = ["local/plugins.sh"]
      }

      resources {
        cpu    = "128"
        memory = "64"
        // memory_max = "256"
      } // plugin task resources
    }   // task

    task "launch" {
      vault {}
      env {
        CASC_JENKINS_CONFIG = "alloc/data/jenkins.yml"
        JENKINS_HOME        = "alloc/jenkins"
        CACHE_DIR           = "local/"
      }
      driver = "java"
      config {
        jvm_options = [
          "-Xmx2048m",
          "-Xms256m",
          "-Dhudson.footerURL=https://hashiatho.me",
          "-Dhudson.model.WorkspaceCleanupThread.disabled=true",
          "-Dhudson.slaves.ConnectionActivityMonitor.timeToPing=30000",
          "-Djenkins.install.runSetupWizard=false",
          "-Djenkins.security.SystemReadPermission=true",
          "-Djenkins.ui.refresh=true"
        ]
        jar_path = "alloc/jenkins/jenkins.war"
        args = [
          "--httpPort=${NOMAD_PORT_ui}",
          "--httpListenAddress=${NOMAD_IP_ui}"
        ]
      }

      volume_mount {
        volume      = "casc"
        destination = "/usr/share/jenkins"
        read_only   = false
      }
      resources {
        cpu    = "2048"
        memory = "2048"
        // memory_max = "2048"
      } // launch task resources
      service {
        port = "ui"
        name = "jenkins-controller"
        check {
          type     = "http"
          port     = "ui"
          path     = "/prometheus/"
          interval = "10s"
          timeout  = "5s"
        }
        on_update = "require_healthy"
        tags      = ["urlprefix-/jenkins"]
      } // jenkins ui service

      service {
        port = "agent"
        name = "jenkins-controller-inbound-agent"
        check {
          type      = "http"
          port      = "agent"
          path      = "/"
          on_update = "require_healthy"
          interval  = "30s"
          timeout   = "5s"
        }
      }

      artifact {
        source      = "https://get.jenkins.io/war-stable/${var.jenkins_war.war_version}/jenkins.war"
        destination = "alloc/jenkins/jenkins.war"
        mode        = "file"
        options {
          checksum = "sha256:${var.jenkins_war.war_sha256}"
        }
      }

      template {
        data        = file("jenkins.yml.tmpl")
        destination = "alloc/data/jenkins.yml"
        change_mode = "restart"
      } // jenkins.yml template
    }
  }
}
