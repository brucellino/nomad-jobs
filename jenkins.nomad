job "jenkins" {
  datacenters = ["dc1"]
  priority    = 100
  type        = "service"

  constraint {
    attribute = "${attr.driver.java.version}"
    operator = ">="
    value = "1.11"

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

    network {
      port "server" {
        static = 8080
      }
    }

    ephemeral_disk {
      sticky  = true
      migrate = true
      size    = 1000
    }

    task "prepare-plugin-ref" {
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      resources {
        cores  = 1
        memory = 1024
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
      template {
        change_mode = "restart"
        data = <<EOH
blueocean
blueocean-commons
blueocean-config
blueocean-core-js
blueocean-dashboard
blueocean-display-url
blueocean-events
blueocean-git-pipeline
blueocean-github-pipeline
blueocean-i18n
blueocean-jwt
blueocean-personalization
blueocean-pipeline-api-impl
blueocean-pipeline-editor
blueocean-pipeline-scm-api
blueocean-rest
blueocean-rest-impl
blueocean-web
branch-api
configuration-as-code
credentials
credentials-binding
dashboard-view
display-url-api
durable-task
github
github-api
github-autostatus
github-branch-source
greenballs
hashicorp-vault-pipeline
hashicorp-vault-plugin
job-dsl
metrics
monitoring
pipeline-build-step
pipeline-github
pipeline-github-lib
pipeline-githubnotify-step
pipeline-graph-analysis
pipeline-milestone-step
pipeline-model-api
pipeline-model-definition
pipeline-model-extensions
pipeline-rest-api
pipeline-stage-step
pipeline-stage-tags-metadata
pipeline-stage-view
pipeline-utility-steps
trilead-api
workflow-api
workflow-basic-steps
workflow-cps
workflow-cps-global-lib
workflow-durable-task-step
workflow-job
workflow-multibranch
workflow-scm-step
workflow-step-api
workflow-support
EOH
        destination = "local/plugins.txt"
      }
      driver = "raw_exec"

      config {
        command = "java"
        args    = [
          "-jar",
          "local/jenkins-plugin-manager.jar",
          "--skip-failed-plugins",
          "--verbose",
          "--war", "local/jenkins.war",
          "--plugin-file", "local/plugins.txt",
          "-d",
          "local/plugins"
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
        tags = ["jenkins", "ci"]
        port = "server"

        check {
          path     = "/login"
          name     = "alive"
          type     = "tcp"
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

      // volume_mount {
      //   volume      = "casc"
      //   destination = "/jenkins_casc"
      //   read_only   = true
      // }
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

        destination = "local/jenkins_casc/jenkins.yml"
      }

      env {
        CASC_JENKINS_CONFIG = "local/jenkins_casc/jenkins.yml"
        JENKINS_HOME        = "local"
      }

      // csi_plugin {
      //   id = "jenkins_home"
      //   type = "node"
      //   mount_dir = "/csi"
      // }
      resources {
        cores  = 3
        memory = 2048 # 256MB
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
