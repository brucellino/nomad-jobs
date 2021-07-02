job "jenkins-java" {
  datacenters = ["dc1"]
  priority = 100
  type = "service"
  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "arm64"
  }
  update {
    max_parallel = 1
    min_healthy_time = "10m"
    healthy_deadline = "15m"
    progress_deadline = "20m"
    auto_revert = false
    canary = 1
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

    network {
      port "server" {
        static = 8080
        to = 80
      }
    }

    service {
      name = "jenkins"
      tags = ["jenkins", "ci"]
      port = "server"

      check {
        path = "/login"
        name     = "alive"
        type     = "tcp"
        interval = "60s"
        timeout  = "10s"
        port = "server"
      }
    }

    ephemeral_disk {
      sticky = true
      migrate = true
      size = 1000
    }
    task "prepare-plugin-ref" {
      lifecycle {
        hook = "prestart"
        sidecar = false
      }

      artifact {
        source = "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.9.0/jenkins-plugin-manager-2.9.0.jar"
        destination = "local/jenkins-plugin-manager.jar"
        mode = "file"
      }
      driver = "raw_exec"
      config {
        command = "sh"
        args = ["-c", "mkdir -vp /usr/share/jenkins/ref/plugins ; java -jar local/jenkins-plugin-manager.jar -p blueocean blueocean-commons blueocean-config blueocean-core-js blueocean-dashboard blueocean-display-url blueocean-events blueocean-git-pipeline blueocean-github-pipeline blueocean-i18n blueocean-jwt blueocean-personalization blueocean-pipeline-api-impl blueocean-pipeline-editor blueocean-pipeline-scm-api blueocean-rest blueocean-rest-impl blueocean-web branch-api configuration-as-code credentials  credentials-binding dashboard-view display-url-api durable-task github github-api github-autostatus github-branch-source greenballs hashicorp-vault-pipeline hashicorp-vault-plugin job-dsl metrics monitoring pipeline-build-step pipeline-github pipeline-github-lib pipeline-githubnotify-step pipeline-graph-analysis pipeline-milestone-step pipeline-model-api pipeline-model-definition pipeline-model-extensions pipeline-rest-api pipeline-stage-step pipeline-stage-tags-metadata pipeline-stage-view pipeline-utility-steps trilead-api workflow-api workflow-basic-steps workflow-cps workflow-cps-global-lib workflow-durable-task-step workflow-job workflow-multibranch workflow-scm-step workflow-step-api workflow-support"]
      }
    }
    task "jenkins-controller" {
      driver = "java"
      config {
        jar_path = "local/jenkins.war"
        jvm_options = ["-Xmx2048m", "-Xms256m"]
      }
      artifact {
        source = "https://get.jenkins.io/war-stable/2.277.1/jenkins.war"
      }

      logs {
        max_files     = 10
        max_file_size = 15
      }
      volume_mount {
        volume = "casc"
        destination = "/jenkins_casc"
        read_only = true
      }
      env {
        CASC_JENKINS_CONFIG = "/jenkins_casc/jenkins.yml"
      }
      csi_plugin {
        id = "jenkins_home"
        type = "node"
        mount_dir = "/csi"
      }
      resources {
        cpu    = 3500 # 500 MHz
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
