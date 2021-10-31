job "jenkins-java" {
  datacenters = ["dc1"]
  priority    = 100
  type        = "service"

  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "arm"
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
        source      = "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.9.0/jenkins-plugin-manager-2.9.0.jar"
        destination = "local/jenkins-plugin-manager.jar"
        mode        = "file"
      }

      artifact {
        source      = "https://get.jenkins.io/war-stable/2.289.1/jenkins.war"
        destination = "local/jenkins.war"
        mode        = "file"
      }

      driver = "raw_exec"

      config {
        command = "java"
        args    = ["-jar", "local/jenkins-plugin-manager.jar", "--verbose", "--war", "local/jenkins.war", "-p", "blueocean blueocean-commons blueocean-config blueocean-core-js blueocean-dashboard blueocean-display-url blueocean-events blueocean-git-pipeline blueocean-github-pipeline blueocean-i18n blueocean-jwt blueocean-personalization blueocean-pipeline-api-impl blueocean-pipeline-editor blueocean-pipeline-scm-api blueocean-rest blueocean-rest-impl blueocean-web branch-api configuration-as-code credentials  credentials-binding dashboard-view display-url-api durable-task github github-api github-autostatus github-branch-source greenballs hashicorp-vault-pipeline hashicorp-vault-plugin job-dsl metrics monitoring pipeline-build-step pipeline-github pipeline-github-lib pipeline-githubnotify-step pipeline-graph-analysis pipeline-milestone-step pipeline-model-api pipeline-model-definition pipeline-model-extensions pipeline-rest-api pipeline-stage-step pipeline-stage-tags-metadata pipeline-stage-view pipeline-utility-steps trilead-api workflow-api workflow-basic-steps workflow-cps workflow-cps-global-lib workflow-durable-task-step workflow-job workflow-multibranch workflow-scm-step workflow-step-api workflow-support", "-d", "local/plugins"]
      }
    }

    task "jenkins-controller" {
      driver = "raw_exec"

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

      config {
        command = "java"

        args = [
          "-jar",
          "local/jenkins.war",
          "-Xmx2048m",
          "-Xms256m",
          "-Dhudson.footerURL=https://hashiatho.me",
          "-Dhudson.model.WorkspaceCleanupThread.disabled=true",
          "-Dhudson.slaves.ConnectionActivityMonitor.timeToPing=30000",
          "-Djenkins.install.runSetupWizard=false",
          "-Djenkins.security.SystemReadPermission=true",
          "-Djenkins.ui.refresh=true",
        ]
      }

      artifact {
        source      = "https://get.jenkins.io/war-stable/2.289.1/jenkins.war"
        destination = "local/jenkins.war"
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
