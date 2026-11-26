// Indico image for platform deployment
packer {
  required_plugins {
    docker = {
      source = "github.com/hashicorp/docker"
      version = "~> 1"
    }
  }
}

local "github_token" {
  expression = vault("hashiatho.me-v2/data/github", "indicotoken")
  sensitive = true
}
source "docker" "indico-base-amd64" {
  image = "ubuntu:24.04" // https://docs.getindico.io/en/stable/installation/production/deb/#debian-ubuntu
  commit = true
  platform = "linux/amd64" #linux/arm64
  changes = [
    "ENTRYPOINT /bin/bash",
    "USER indico",
    "WORKDIR /opt/indico"
  ]
}
source "docker" "indico-base-arm64" {
  image = "ubuntu:24.04" // https://docs.getindico.io/en/stable/installation/production/deb/#debian-ubuntu
  commit = true
  platform = "linux/arm64"
  changes = [
    "ENTRYPOINT /bin/bash",
    "USER indico",
    "WORKDIR /opt/indico"
  ]
}

build {
  sources = ["source.docker.indico-base-amd64", "source.docker.indico-base-arm64"]

  # Add mise
  provisioner "shell" {
    inline = [
      "apt update -qq",
      "apt install -yy -qq extrepo",
      "extrepo enable mise",
      "apt update -qq",
      "apt install -y mise",
    ]
  }

  # Provide the Mise configuration file
  provisioner "file" {
    source = "mise.indico.toml"
    destination = "/mise.toml"
  }
  # And the application dependencies
  provisioner "file" {
    source = "requirements.txt"
    destination = "/requirements.txt"
  }

  # Bootstrap the machine
  provisioner "shell" {
    inline = [
      "mise trust",
      "mise bootstrap",
      "mise bootstrap packages apply",
      "mise tasks run install"
    ]
  }

  provisioner "shell" {
    inline = [
      "eval $(mise activate)",
      "mise doctor"
    ]
  }
  post-processors {
    post-processor "docker-tag" {
      repository = "ghcr.io/hashi-at-home/indico"
      tags = ["latest"]
    }
    post-processor "docker-push" {
      login = true
      login_server = "ghcr.io"
      login_username = "brucellino"
      login_password = local.github_token
    }
  }
}
