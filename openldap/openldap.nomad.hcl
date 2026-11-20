// OpenLDAP server job designed to act as a backing service to the
// Platform identity services (Keycloak endpoints)
// This LDAP server is designed to contain only the internal platform
// human identities.
// All other users of platform services and workloads are authenticated using
// Institutional identity providers.
job "openldap" {
  datacenters = ["dc1"]
  type        = "service"

  // always reschedule the job if it fails
  reschedule {
    unlimited      = true
    interval       = "1h"
    delay          = "20s"
    delay_function = "constant"
  }

  update {
    max_parallel     = 2
    min_healthy_time = "5s"
    healthy_deadline = "3m"
    auto_revert      = true
    auto_promote     = true
    canary           = 1
  }

  // We have a single group of tasks which will be allocated onto a node.
  group "openldap" {
    count = 1

    // always restart the groups tasks if they fail.
    restart {
      attempts         = 3
      interval         = "5m"
      delay            = "30s"
      mode             = "delay"
      render_templates = true
    }

    // Expose the ldap port
    network {
      port "ldap" {
        to = 389
      }

      port "ldaps" {
        to = 636
      }
    }

    task "ldap-server" {
      driver = "docker"
      config {
        image = "osixia/openldap"
        ports = ["ldap", "ldaps"]
        args  = ["--copy-service", "--loglevel", "debug"]
        volumes = [
          "local/bootstrap.ldif:/container/service/slapd/assets/config/bootstrap/ldif/99-custom.ldif"
        ]
      }
      env {
        LDAP_ADMIN_PASSWORD            = "admin" # pragma: allowlist secret
        LDAP_ADMIN_USERNAME            = "admin"
        LDAP_BASE_DN                   = "dc=example,dc=org"
        LDAP_DOMAIN                    = "example.org"
        LDAP_TLS                       = false
        LDAP_REMOVE_CONFIG_AFTER_SETUP = false
        OPENLDAP_BOOTSTRAP_SCRIPTS_DIR = "/local"
      }

      resources {
        cpu    = 1000
        memory = 1024
      }

      service {
        name = "ldap-server"
        tags = ["urlprefix-/ldap-server strip=/ldap-server", "traefik-enable=true", "traefik.http.routers.ldap-server.service=ldap-server"]
        port = "LDAP"
        check {
          name     = "alive"
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      } //service
      template {
        change_mode = "noop"
        perms       = "755"
        destination = "/local/bootstrap.ldif"
        data        = file("ldif/bootstrap.ldif")
      } //template
    }   // server task
  }     // group
}
