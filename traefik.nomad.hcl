job "traefik-external" {
  type        = "service"
  datacenters = ["dc1"]
  group "traefik" {
    network {
      port "http" {
        static = 80
      }
      port "https" {
        to = 443
      }

      port "dashboard" {
        static = 8080
      }
    }

    task "traefik" {
      service {
        name = "traefik-secure"
        port = "https"
        check {
          name     = "alive"
          type     = "tcp"
          port     = "http"
          interval = "10s"
          timeout  = "2s"
        }
      }
      service {
        name = "traefik"
        port = "http"
        check {
          name     = "alive"
          type     = "tcp"
          port     = "http"
          interval = "10s"
          timeout  = "2s"
        }
      }
      service {
        name = "dashboard"
        port = "dashboard"
        check {
          name     = "alive"
          type     = "http"
          path     = "/dashboard"
          port     = "dashboard"
          interval = "10s"
          timeout  = "2s"
        }
      }

      resources {
        cpu    = 1000
        memory = 1024
      }

      vault {}

      driver         = "docker"
      shutdown_delay = "15s"
      config {
        image = "traefik:v3.7"
        ports = ["http", "https", "dashboard"]
        args  = ["--configFile=/local/traefik.yml"]
      }
      # Generate Traefik config from template
      template {
        data        = <<EOH
---
global:
  checkNewVersion: true
entryPoints:
  http:
    address: ":{{ env "NOMAD_PORT_http" }}"
    observability:
      accessLogs: true
      metrics: true
      tracing: true
  websecure:
    address: ":{{ env "NOMAD_PORT_https" }}"
    http:
      tls: true
# http:
#   middlewares:
#     redirect-https:
#       redirectScheme:
#         scheme: https
#         permanent: true
routers:
  dashboard:
    rule: PathPrefix(`/api`) || PathPrefix(`/dashboard`))
    service: api@internal
    redirect-web:
      tls:
        certResolver: hah
      entryPoints:
        - http
#       rule: "HostRegexp(`.+`)"
#       middlewares:
#         - redirect-https
#       service: noop
#       priority: 1
api:
  dashboard: true
  insecure: true
#
ping: {}
#
providers:
  consulCatalog:
    endpoint:
      address:  172.17.0.1:8500
    exposedByDefault: false
accesslog:
  format: json
log:
  level: INFO
tracing:
  addInternals: true
metrics:
  prometheus:
    addentrypointslabels: true
certificatesResolvers:
  hah:
    tailscale: {}
EOH
        destination = "local/traefik.yml"
      }

    }
  }
}
