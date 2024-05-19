variable "glue" {
  type = map(string)
  description = "Release of the GLUE versions to use"
  default = {
    url = "https://github.com/EGI-Federation/glue-schema/archive/refs/tags"
    version = "2.1.1"
  }
}

variable "slapd" {
  description = "configuration items for slapd"
  type = object({
    bdii_var_dir = string
    db_dir = string,
    db_conf_dir = string,
    db_entries = list(string)
    port = string,
    ipv6_support = bool
  })

  default = {
    # These go under the job alloc directory
    bdii_var_dir = "data/var/lib/bdii/"
    db_dir = "data/var/lib/bdii/db"
    db_conf_dir = "data/etc/bdii"
    db_entries = [
      "stats",
      "glue",
      "stats",
      "grid"
    ],
    port = "2170",
    ipv6_support = false
    schemas_dir = "data/etc/bdii/schemas"
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
      port "slapd" {
        to = 2170
      }
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

    reschedule {
      unlimited = true
      interval = "10m"
      delay = "30s"
      delay_function = "constant"
    }

    task "configure-slapd" {
      env {
        BDII_VAR_DIR = "${var.slapd.bdii_var_dir}"
        SLAPD_DB_DIR = "${var.slapd.db_dir}"
      }
      # This task provisions the configuration files required for the
      # configuration of the LDAP server
      artifact {
        # This creates ${NOMAD_ALLOC_DIR}/glue-schema
        source = "${var.glue.url}/v${var.glue.version}.tar.gz"
        destination = "${NOMAD_ALLOC_DIR}/scratch"
      }
      template {
        data = file("provision_config_files.sh.tmpl")
        destination = "${NOMAD_ALLOC_DIR}/provision_config_files.sh"
        perms = "777"
      }
      lifecycle {
        hook = "prestart"
        sidecar = false
      }
      driver = "exec"
      config {
        command = "${NOMAD_ALLOC_DIR}/provision_config_files.sh"
      }
      volume_mount {
        volume = "ldap"
        destination = "/alloc/data"
        propagation_mode = "bidirectional"
      }
    }

    task "ldap" {
      # The "driver" parameter specifies the task driver that should be used to
      # run the task.
      driver = "docker"
      config {
        image = "bitnami/openldap:2.6"
        ports = ["slapd"]
        auth_soft_fail = true
      }
      env {
        LDAP_PORT_NUMBER = "${NOMAD_PORT_slapd}"
        // LDAP_EXTRA_SCHEMAS = "inetorgperson,nis,cosine"
        LDAP_ADD_SCHEMAS = "yes"
        LDAP_CUSTOM_SCHEMA_DIR = "/etc/glue/LDAP_ADD_SCHEMAS"
        LDAP_LOGLEVEL = 2048
        LDAP_ENABLE_ACCESSLOG = "yes"
        LDAP_ACCESSLOG_LOGOPS = "all"
        BDII_VAR_DIR = "${var.slapd.bdii_var_dir}"
        SLAPD_DB_DIR = "${var.slapd.db_dir}"
      }
      logs {
        max_files     = 10
        max_file_size = 15
      }

      identity {
        env  = true
        file = true
      }
      resources {
        cpu    = 125 # 500 MHz
        memory = 256 # 512MB
      }

      volume_mount {
        volume = "ldap"
        destination = "/alloc/data"
        propagation_mode = "bidirectional"
      }
    }
  }
}
