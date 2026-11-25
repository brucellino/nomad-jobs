job "kroki" {
  ui {
    description = "Kroki provides a unified API with support for BlockDiag (BlockDiag, SeqDiag, ActDiag, NwDiag, PacketDiag, RackDiag), BPMN, Bytefield, C4 (with PlantUML), D2, DBML, Diagrams.net (experimental), Ditaa, Erd, Excalidraw, GoAT, GraphViz, Lini, Mermaid, Nomnoml, Pikchr, PlantUML, SvgBob, Symbolator, UMLet, Vega, Vega-Lite, WaveDrom and WireViz…​ and more to come!"
    link {
      label = "Repo"
      url   = "https://github.com/yuzutech/kroki"
    }
  }
  meta {
    repo           = "https://github.com/brucellino/nomad-jobs"
    job-definition = "kroki/kroki.nomad.hcl"
  }
  group "gateway" {
    count = 1
    network {
      port "http" {
        to = 8000
      }
    }
    task "kroki" {
      resources {
        cpu    = 100
        memory = 512
      }
      shutdown_delay = "5s"
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
        image              = "yuzutech/kroki:0.37.1"
        ports              = ["http"]
        image_pull_timeout = "30s"
      }
    }
  }
}
