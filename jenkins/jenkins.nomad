variable "jenkins_plugins" {
  type = list(string)
  description = "List of plugin names for jenkins"
}

job "jenkins" {
  datacenters = ["dc1"]
  priority    = 100
  type        = "service"

  constraint {
    attribute = "${attr.driver.java.version}"
    operator = ">="
    value = "11"

  }

  update {
    max_parallel      = 1
    min_healthy_time  = "20m"
    healthy_deadline  = "30m"
    progress_deadline = "40m"
    auto_revert       = false
    canary            = 1
  }

  migrate {
    max_parallel = 2
  }

  group "jenkins" {
    count = 1
    volume "casc" {
      type = "host"
      read_only = false
      source = "jenkins_casc"
    }

    volume "jenkins_home" {
      type = "host"
      read_only = false
      source = "jenkins_config"
    }
    network {
      port "server" {
        to = 8080
      }
    }

    ephemeral_disk {
      sticky  = true
      migrate = true
      size    = 1000
    }

    task "prepare-plugin-ref" {
      template {
        change_mode = "restart"
        data = "yamlencode(var.jenkins_plugins)"
        destination = "${NOMAD_ALLOC_DIR}/casc/plugins.txt"
      }
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      resources {
        cpu = 200
        memory = 128
      }

      artifact {
        source      = "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.12.8/jenkins-plugin-manager-2.12.8.jar"
        destination = "local/jenkins-plugin-manager.jar"
        mode        = "file"
      }

      artifact {
        source      = "https://get.jenkins.io/war-stable/2.346.1/jenkins.war"
        options {
          checksum = "sha256:176e2ce5c23d3c0b439befe0461e7ed1f53ac3091db05980198c23c7fde53b27"
        }
        destination = "local/jenkins.war"
        mode        = "file"
      }


      volume_mount {
        volume = "casc"
        destination = "${NOMAD_ALLOC_DIR}/casc"
        read_only = false
      }

      volume_mount {
        volume = "jenkins_home"
        destination = "${NOMAD_ALLOC_DIR}/jenkins_home"
        read_only = false
      }

      driver = "java"

      config {
        jar_path = "local/jenkins-plugin-manager.jar"
        args = [
          "--skip-failed-plugins",
          "--verbose",
          "--war", "local/jenkins.war",
          "--plugin-file", "${NOMAD_ALLOC_DIR}/casc/plugins.txt",
          "-d",
          "${NOMAD_ALLOC_DIR}/jenkins_home/plugins/"
        ]
      }
    }

    task "jenkins-controller" {
      driver = "java"
      config {
        jar_path = "local/jenkins.war"
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
      }
      service {
        name = "jenkins-java-controller"
        tags = ["jenkins", "ci", "urlprefix-/jenkins"]
        port = "server"

        check {
          path     = "/"
          name     = "alive"
          type     = "http"
          interval = "60s"
          timeout  = "10s"
          port     = "server"
        }
      }

      artifact {
        source      = "https://get.jenkins.io/war-stable/2.346.1/jenkins.war"
        destination = "local/jenkins.war"
        mode = "file"
      }

      logs {
        max_files     = 10
        max_file_size = 15
      }


      template {
        data = <<EOH
---
jenkins:
  systemMessage: "This the best ever message"
  authorizationStrategy:
    roleBased:
      roles:
        global:
          - name: "admin"
            description: "Jenkins administrators"
            permissions:
              - "Overall/Administer"
            assignments:
              - "admin"
  securityRealm:
    local:
      allowsSignup: false
      users:
        - id: "admin"
          password: "1234"
EOH

        destination = "${NOMAD_ALLOC_DIR}/casc/jenkins.yml"
      }

      env {
        CASC_JENKINS_CONFIG = "${NOMAD_ALLOC_DIR}/casc/jenkins.yml"
        JENKINS_HOME        = "${NOMAD_ALLOC_DIR}/jenkins_home/"
      }
      volume_mount {
        volume = "casc"
        destination = "${NOMAD_ALLOC_DIR}/casc"
        read_only = false
      }

      volume_mount {
        volume = "jenkins_home"
        destination = "${NOMAD_ALLOC_DIR}/jenkins_home"
        read_only = false
      }

      // csi_plugin {
      //   id = "jenkins_home"
      //   type = "node"
      //   mount_dir = "/csi"
      // }
      resources {
        cores  = 2
        memory = 1048 # 256MB
      }

      restart {
        interval = "30m"
        attempts = 5
        delay    = "10m"
        mode     = "fail"
      }
    }
  }
}
