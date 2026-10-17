# See
# https://forgejo.org/docs/latest/admin/installation/docker/
# https://codeberg.org/forgejo/-/packages/container/forgejo/17.0.0
job "forgejo" {
  group "server" {
    network {
      port "server" {
        to = 3000
      }
    }
    task "forgejo" {
      resources {
        cpu    = 1000
        memory = 1024
      }
      shutdown_delay = "30s"
      service {
        port = "server"
      }
      driver = "docker"
      config {
        image = "codeberg.org/forgejo/forgejo:16"
        ports = ["server"]
      }
    }
  }
}
