variable "ghcr_token" {
  type        = string
  description = "Github Container Registry Auth Token"
}

job "qa" {
  datacenters = ["dc1"]
  type        = "service"

  update {
    max_parallel      = 2
    min_healthy_time  = "10s"
    healthy_deadline  = "15m"
    progress_deadline = "20m"
    auto_revert       = true
    auto_promote      = true
    canary            = 1
  }

  migrate {
    max_parallel     = 2
    health_check     = "checks"
    min_healthy_time = "10s"
    healthy_deadline = "15m"
  }

  group "db" {
    affinity {
      attribute = "${attr.kernel.arch}"
      value     = "x86_64"
      weight    = 75
    }
    network {
      port "db" {
        to = 27017
      }
    }

    service {
      // provider = "nomad"
      name = "mongo"
      port = "db"
      check {
        name     = "mongo server"
        type     = "tcp"
        interval = "20s"
        timeout  = "8s"
      }
    }

    task "mongo" {
      driver = "docker"

      constraint {
        attribute = "${attr.kernel.arch}"
        operator  = "set_contains_any"
        value     = "aarch64,x86_64"
      }

      config {
        image              = "mongodb/mongodb-community-server:5.0.10-ubuntu2004"
        ports              = ["db"]
        image_pull_timeout = "10m"
      }

      vault {}

      template {
        data        = <<EOF
MONGO_INITDB_ROOT_USERNAME=root
MONGO_INITDB_ROOT_PASSWORD={{with secret "kv/data/default/mongo/config"}}{{.Data.data.root_password}}{{end}}
EOF
        destination = "secrets/env"
        env         = true
      }
    }
  }

  group "api" {
    count = 1

    restart {
      attempts = 2
      interval = "5m"
      delay    = "15s"
      mode     = "fail"
    }

    ephemeral_disk {
      size = 200
    }

    network {
      mode = "bridge"
      port "http" {
        to = "8080"
      }
    }
    # The "service" block enables Consul Connect.
    service {
      name = "test-api"
      port = "8080"

      // check {
      //   name     = "alive"
      //   type     = "tcp"
      //   task     = "task-api"
      //   interval = "10s"
      //   timeout  = "2s"
      // }

      // connect {
      //   sidecar_service {}
      // }
    }


    task "test-api" {
      driver = "docker"
      env {
        PORT = "${NOMAD_PORT_http}"
      }
      config {
        ports              = ["http"]
        image              = "ghcr.io/brucellino/qa-api:latest"
        auth_soft_fail     = true
        image_pull_timeout = "10m"
        auth {
          username = "brucellino"
          password = var.ghcr_token
        }
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
        memory = 256 # 256MB
      }
    }
  }
}
