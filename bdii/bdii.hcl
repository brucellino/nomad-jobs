variable "bdii" {
  description = "Configuration items for BDII"
  type = object({
    version = string
    files = list(string)
  })

  default = {
    version = "6.0.1"
    files = [
      "BDII.schema"
    ]
  }
}

variable "glue" {
  description = "Glue schema configuration items"
  type = object({
    url = string
    version = string
    schemas = list(string)
  })
  default = {
    url = "https://github.com/EGI-Federation/glue-schema/archive/refs/tags"
    version = "2.1.1"
    schemas = [
      "GLUE20.schema",
      "Glue-CE.schema",
      "Glue-CESEBind.schema",
      "Glue-MDS.schema",
      "Glue-SE.schema"
    ]
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
    schemas_dir = string
  })

  default = {
    # These go under the job alloc directory
    bdii_var_dir = "var/lib/bdii/"
    db_dir = "var/lib/bdii/db"
    db_conf_dir = "etc/bdii"
    db_entries = [
      "stats",
      "glue",
      "stats",
      "grid"
    ],
    port = "2170",
    ipv6_support = false
    schemas_dir = "local/schemas"
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

    task "ldap" {
      # The "driver" parameter specifies the task driver that should be used to
      # run the task.
      artifact {
        source = "github.com/EGI-Federation/glue-schema.git//etc/ldap/schema"
        destination = "local/schema"
        mode = "dir"
      }

      artifact {
        # BDII Schema directly from EGI-Foundation/bdii
        source = "https://raw.githubusercontent.com/EGI-Federation/bdii/v${var.bdii.version}/etc/BDII.schema"
        destination = "local/schema/BDII.schema"
        mode = "file"
      }

      artifact {
        # slapd config EGI-Foundation/bdii
        source = "https://raw.githubusercontent.com/EGI-Foundation/bdii/v${var.bdii.version}/etc/bdii-slapd.conf"
        destination = "/local/etc/bdii-slapd.conf"
        mode = "file"
      }

      template {
        data = file("provision_config_files.sh.tmpl")
        destination = "/docker-entrypoint-initdb.d/start.sh"
        perms = "777"
      }

      template {
        data = file("bdii-slapd.conf")
        destination = "local/bdii-slapd.conf"
        perms = "0644"
      }

      driver = "docker"
      config {
        image = "bitnami/openldap:2.6"
        ports = ["slapd"]
        auth_soft_fail = true
      }
      env {
        LDAP_PORT_NUMBER = "${NOMAD_PORT_slapd}"
        // LDAP_CUSTOM_SCHEMA_FILE = "Glue-CORE"
        LDAP_ADD_SCHEMAS = "yes"
        // LDAP_EXTRA_SCHEMAS = "Glue-CORE"
        LDAP_LOGLEVEL = 2048
        LDAP_ENABLE_ACCESSLOG = "yes"
        LDAP_ACCESSLOG_LOGOPS = "all"
        BDII_VAR_DIR = "${var.slapd.bdii_var_dir}"
        SLAPD_DB_DIR = "${var.slapd.db_dir}"
        // LDAP_CUSTOM_SCHEMA_DIR = "/local/schema/"
        // BITNAMI_DEBUG = true
        LDAP_SKIP_DEFAULT_TREE = "yes"
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
        cpu    = 500 # 500 MHz
        memory = 512 # 512MB
      }

      volume_mount {
        volume = "ldap"
        destination = "${NOMAD_ALLOC_DIR}/mount-data"
        propagation_mode = "bidirectional"
      }
    }
  }
}
