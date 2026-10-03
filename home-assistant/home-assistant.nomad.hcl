# Hashi@Home assistant
job "home-assistant" {
  group "server" {
    network {
      port "web" {
        to = 8123
      }
    }
    task "home-assistant" {
      driver         = "docker"
      shutdown_delay = "1m"
      service {
        port = "web"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.ha.entrypoints=http",
          "traefik.http.routers.ha.rule=PathPrefix(`/hass`)",
          "traefik.http.middlewares.ha-stripprefix.stripprefix.prefixes=hss",
          "traefik.http.routers.ha.middlewares=ha-stripprefix",
          # "traefik.http.routers.ha.middlewares=ha-rewrite",
          # "traefik.http.middlewares.ha-rewrite.replacepathregex.regex=^/(.*)",
          # "traefik.http.middlewares.ha-rewrite.replacepathregex.replacement=$1"
        ]
        check {
          name     = "ha-alive"
          type     = "tcp"
          port     = "web"
          interval = "10s"
          timeout  = "2s"
        }

        check {
          name     = "ha-healthy"
          type     = "http"
          port     = "web"
          path     = "/"
          interval = "10s"
          timeout  = "2s"
        }
      }
      resources {
        cpu    = 2
        memory = 2048
      }
      config {
        image = "ghcr.io/home-assistant/home-assistant:stable"
        ports = ["web"]
      }
    }
  }
}
