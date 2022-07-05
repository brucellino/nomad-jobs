job "jenkins" {

  update {
    max_parallel = 1
    health_check = "checks"
    auto_revert = true
    auto_promote = true
    canary = 1
  }

  constraint {
    attribute  = "${attr.unique.hostname}"
    operator = "regexp"
    value = "^turing.*"
  }

  datacenters = ["dc1"]
  type = "service"
  group "main" {
    count = 1
    network {
      port "ui" {
        static = "8080"
      }
      mode = "host"
    }

    volume "casc" {
      type      = "host"
      read_only = false
      source    = "jenkins_casc"
    }

    task "controller" {
      driver = "exec"
      volume_mount {
        volume      = "casc"
        destination = "/usr/share/jenkins"
        read_only   = false
      }

      artifact {
        source = "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.12.8/jenkins-plugin-manager-2.12.8.jar"
        destination = "alloc/data/jenkins-plugin-manager.jar"
        mode = "file"
      }

      artifact {
        source = "https://get.jenkins.io/war-stable/2.346.1/jenkins.war"
        destination = "alloc/data/jenkins.war"
        mode = "file"
        options {
          checksum = "sha256:176e2ce5c23d3c0b439befe0461e7ed1f53ac3091db05980198c23c7fde53b27"
        }
      }
      template {
        data = "{{ key \"jenkins/plugins\" }}"
        destination = "local/plugins.txt"
        change_mode = "restart"
      }
      env {
        CASC_JENKINS_CONFIG = "alloc/data/jenkins.yml"
        JENKINS_HOME        = "/usr/share/jenkins"
        CACHE_DIR = "local/"
      }
      template {
        data = <<EOF
#!/bin/bash
pwd
set -eou pipefail
mkdir -vp /usr/share/jenkins/plugins
java -jar alloc/data/jenkins-plugin-manager.jar \
     --war alloc/data/jenkins.war \
     --plugin-file local/plugins.txt \
     --skip-failed-plugins \
     --verbose \
     -d /usr/share/jenkins/plugins/
echo "plugins installed"

java \
  -Xmx1024m \
  -Xms256m \
  -Dhudson.footerURL=https://hashiatho.me \
  -Dhudson.model.WorkspaceCleanupThread.disabled=true \
  -Dhudson.slaves.ConnectionActivityMonitor.timeToPing=30000 \
  -Djenkins.install.runSetupWizard=false \
  -Djenkins.security.SystemReadPermission=true \
  -Djenkins.ui.refresh=true \
  -jar alloc/data/jenkins.war \
  --httpPort=${NOMAD_PORT_ui}
EOF
        destination = "local/script.sh"
        perms = "0777"
      }

      config {
        command = "/bin/bash"
        args = ["local/script.sh"]
      }

      service {
        port = "ui"

        check {
          type = "http"
          port = "ui"
          path = "/prometheus/"
          interval = "10s"
          timeout = "5s"
        }

        on_update = "require_healthy"

        tags = ["urlprefix-/jenkins"]
      }
      template {
        data = <<EOH
---
jenkins:
  agentprotocols:
    - "JNLP4-connect"
    - "Ping"
  numExecutors: 0
  authorizationStrategy:
    globalMatrix:
      permissions:
        - "Overall/Administer:admin"
  crumbIssuer:
    strict:
      checkSessionMatch: false
  remotingSecurity:
    enabled: true
  systemMessage: "This the best ever message"
  securityRealm:
    local:
      allowsSignup: false
      users:
        - id: "admin"
          password: "1234"
  clouds:
    - nomad:
        clientPassword: ""
        name: "nomad"
        nomadUrl: "http://nomad.service.consul:4646"
        prune: false
        serverPassword: ""
        tlsEnabled: false
        workerTimeout: 1

security:
  apiToken:
    creationOfLegacyTokenEnabled: false
    tokenGenerationOnCreationEnabled: false
    usageStatisticsEnabled: true
  globalJobDslSecurityConfiguration:
    useScriptSecurity: true
  sSHD:
    port: -1
unclassified:
  prometheusConfiguration:
    appendParamLabel: true
    appendStatusLabel: true
    collectDiskUsage: true
    collectingMetricsPeriodInSeconds: 60
    countAbortedBuilds: true
    countFailedBuilds: true
    countNotBuiltBuilds: true
    countSuccessfulBuilds: true
    countUnstableBuilds: true
    defaultNamespace: "default"
    fetchTestResults: true
    jobAttributeName: "jenkins_job"
    path: "prometheus"
    processingDisabledBuilds: false
    useAuthenticatedEndpoint: false
EOH
        destination = "alloc/data/jenkins.yml"
      }

      resources {
        cores = 3
        memory = "500"
        memory_max = "1000"
      }
    }
  }
}
