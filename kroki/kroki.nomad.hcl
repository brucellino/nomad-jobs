job "kroki" {
  group "gateway" {
    network {
      port "http" {
        to = 8000
      }
    }
    task "kroki" {
      service {
        port = "http"
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
        image = "yuzutech/kroki"
        ports = ["http"]
      }
    }
  }
}
