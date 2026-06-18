job "kroki" {
  group "gateway" {
    count = 1
    network {
      port "http" {
        to = 8000
      }
    }
    task "kroki" {
      service {
        name = "kroki"
        port = "http"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.kroki.rule=PathPrefix(`/kroki`)",
          "traefik.http.routers.kroki.middlewares=kroki-rewrite",
          "traefik.http.middlewares.kroki-rewrite.replacepathregex.regex=^/kroki(.*)",
          "traefik.http.middlewares.kroki-rewrite.replacepathregex.replacement=$1"
        ]
        check {
          type     = "http"
          name     = "kroki_health"
          path     = "/"
          method   = "GET"
          interval = "10s"
          timeout  = "5s"
        }
      }
      driver = "docker"
      config {
        image = "yuzutech/kroki:0.30.0"
        ports = ["http"]
      }
    }
  }
}
