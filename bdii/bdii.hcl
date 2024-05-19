variable "glue" {
  type = map(string)
  description = "Release of the GLUE versions to use"
  default = {
    url = "https://github.com/EGI-Federation/glue-schema/archive/refs/tags"
    version = "2.1.1"
  }
}

job "bdii" {
  datacenters = ["dc1"]
  type = "service"
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  update {
    max_parallel = 2
    min_healthy_time = "10s"
    healthy_deadline = "5m"
    progress_deadline = "10m"
    auto_revert = true
    auto_promote = true
    canary = 1
  }
  migrate {
    max_parallel = 1
    health_check = "checks"
    min_healthy_time = "10s"
    healthy_deadline = "5m"
  }
  group "site" {
    count = 1

    volume "ldap" {
      type = "host"
      source = "scratch"
      read_only = false
    }

    network {
      port "slapd" {}
    }
    service {
      name     = "bdii"
      tags     = ["site"]
      port     = "slapd"
      provider = "consul"

      check {
        name     = "alive"
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
      }
    }

    restart {
      attempts = 1
      interval = "5m"
      delay = "15s"
      mode = "fail"
    }


    # affinity {
    # attribute specifies the name of a node attribute or metadata
    # attribute = "${node.datacenter}"

    # value specifies the desired attribute value. In this example Nomad
    # will prefer placement in the "us-west1" datacenter.
    # value  = "us-west1"

    # weight can be used to indicate relative preference
    # when the job has more than one affinity. It defaults to 50 if not set.
    # weight = 100
    #  }
    task "ldap" {
      # The "driver" parameter specifies the task driver that should be used to
      # run the task.
      driver = "docker"

      # The "config" block specifies the driver configuration, which is passed
      # directly to the driver to start the task. The details of configurations
      # are specific to each driver, so please see specific driver
      # documentation for more information.
      config {
        image = "bitnami/openldap:2.6"
        ports = ["slapd"]

        # The "auth_soft_fail" configuration instructs Nomad to try public
        # repositories if the task fails to authenticate when pulling images
        # and the Docker driver has an "auth" configuration block.
        auth_soft_fail = true
      }
      artifact {
        source = "${var.glue.url}/v${var.glue.version}.tar.gz"
      }
      env {
        LDAP_PORT_NUMBER = "${NOMAD_PORT_slapd}"
        // LDAP_EXTRA_SCHEMAS = "inetorgperson,nis,cosine"
        LDAP_ADD_SCHEMAS = "yes"
        // LDAP_CUSTOM_SCHEMA_DIR = "/etc/glue/LDAP_ADD_SCHEMAS"
        LDAP_LOGLEVEL = 2048
        LDAP_ENABLE_ACCESSLOG = "yes"
        LDAP_ACCESSLOG_LOGOPS = "all"

      }
      logs {
        max_files     = 10
        max_file_size = 15
      }

      identity {
        env  = true
        file = true
      }

      # The "resources" block describes the requirements a task needs to
      # execute. Resource requirements include memory, cpu, and more.
      # This ensures the task will execute on a machine that contains enough
      # resource capacity.
      #
      # For more information and examples on the "resources" block, please see
      # the online documentation at:
      #
      #     https://developer.hashicorp.com/nomad/docs/job-specification/resources
      #
      resources {
        cpu    = 500 # 500 MHz
        memory = 512 # 512MB
      }

      volume_mount {
        volume = "ldap"
        destination = "/data"
        propagation_mode = "bidirectional"
      }


      #     https://developer.hashicorp.com/nomad/docs/job-specification/template
      #
      # template {
      #   data          = "---\nkey: {{ key \"service/my-key\" }}"
      #   destination   = "local/file.yml"
      #   change_mode   = "signal"
      #   change_signal = "SIGHUP"
      # }

      # The "template" block can also be used to create environment variables
      # for tasks that prefer those to config files. The task will be restarted
      # when data pulled from Consul or Vault changes.
      #
      # template {
      #   data        = "KEY={{ key \"service/my-key\" }}"
      #   destination = "local/file.env"
      #   env         = true
      # }

      # The "vault" block instructs the Nomad client to acquire a token from
      # a HashiCorp Vault server. The Nomad servers must be configured and
      # authorized to communicate with Vault. By default, Nomad will inject
      # The token into the job via an environment variable and make the token
      # available to the "template" block. The Nomad client handles the renewal
      # and revocation of the Vault token.
      #
      # For more information and examples on the "vault" block, please see
      # the online documentation at:
      #
      #     https://developer.hashicorp.com/nomad/docs/job-specification/vault
      #
      # vault {
      #   policies      = ["cdn", "frontend"]
      #   change_mode   = "signal"
      #   change_signal = "SIGHUP"
      # }

      # Controls the timeout between signalling a task it will be killed
      # and killing the task. If not set a default is used.
      # kill_timeout = "20s"
    }
  }
}
