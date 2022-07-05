job "jenkins" {
  datacenters = ["dc1"]
  type        = "batch"

  constraint {
    attribute = "${attr.driver.java.version}"
    operator = ">="
    value = "11"
  }

  group "jenkins" {
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

    task "plugins" {
      driver = "java"

      volume_mount {
        volume = "casc"
        destination = "${NOMAD_TASK_DIR}/casc"
        read_only = false
      }

      volume_mount {
        volume = "jenkins_home"
        destination = "${NOMAD_TASK_DIR}/jenkins_home"
        read_only = false
      }

      template {
        change_mode = "restart"
        data = "{{ key \"jenkins/plugins\" }}"
        destination = "${NOMAD_TASK_DIR}/casc/plugins.yml"
        perms = "644"
      }

      resources {
        cpu = 2000
        memory = 128
      }

      artifact {
        source      = "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.12.8/jenkins-plugin-manager-2.12.8.jar"
        destination = "${NOMAD_TASK_DIR}/local/jenkins-plugin-manager.jar"
        mode        = "file"
      }

      artifact {
        source      = "https://get.jenkins.io/war-stable/2.346.1/jenkins.war"
        options {
          checksum = "sha256:176e2ce5c23d3c0b439befe0461e7ed1f53ac3091db05980198c23c7fde53b27"
        }
        destination = "${NOMAD_TASK_DIR}/local/jenkins.war"
        mode        = "file"
      }
      env {
        CASC_JENKINS_CONFIG = "${NOMAD_TASK_DIR}/casc/jenkins.yml"
        JENKINS_HOME        = "${NOMAD_TASK_DIR}/jenkins_home/"
      }
      config {
        jar_path = "${NOMAD_TASK_DIR}/local/jenkins-plugin-manager.jar"
        args = [
          "--skip-failed-plugins",
          "--verbose",
          "--war", "${NOMAD_TASK_DIR}/local/jenkins.war",
          "--plugin-file", "${NOMAD_TASK_DIR}/casc/plugins.yml",
          "-d",
          "${NOMAD_TASK_DIR}/jenkins_home/plugins/"
        ]
      }
    }
  }
}
