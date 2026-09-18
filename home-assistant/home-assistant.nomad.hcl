# Hashi@Home assistant
job "home-assistant" {
  group "server" {
    network {
      port "web" {
        to = 8123
      }
    }
    task "home-assistant" {
      driver = "docker"
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
