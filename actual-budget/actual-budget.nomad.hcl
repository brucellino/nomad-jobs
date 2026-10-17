# See https://actualbudget.org/docs/
job "actual-budget" {
  group "server" {
    network {
      port "server" {
        to = 5006
      }
    }
    vault {}
    consul {}

    task "actual-server" {
      driver = "docker"
      config {
        image = "actualbudget/actual-server:latest"
        ports = ["server"]
      }
      env {
        ACTUAL_PORT = 5006
      }
      service {
        name = "actual-budget"
        check {
          name     = "actual-health"
          type     = "script"
          command  = "node"
          args     = ["scripts/health-check.js"]
          interval = "30s"
          timeout  = "5s"
        }
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.actual-server.rule=Host(`budget.brucellino.xyz`)",
          "traefik.http.routers.actual-server.rule.PathPrefix(`budget`)",
          "traefik.http.middlewares.actual-server.stripprefix.prefixes=/budget",
          "traefik.http.routers.actual-router.middlewares=actual-server",
          "traefik.http.routers.actual-server.entrypoints=websecure,http"
        ]
      }
      shutdown_delay = "25s"
    }
  }
}
