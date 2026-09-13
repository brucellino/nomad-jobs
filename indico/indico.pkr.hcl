// Indico image for platform deployment
packer {
  required_plugins {
    docker = {
      source = "github.com/hashicorp/docker"
      version = "~> 1"
    }
  }
}

source "docker" "indico-base" {
  image = "ubuntu:24.04" // https://docs.getindico.io/en/stable/installation/production/deb/#debian-ubuntu
  commit = true
  changes = [
    "USER indico"
    "WORKDIR /opt/indico"
  ]
}

build {
  sources = ["source.docker.indico-base"]

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
      "mise tasks run install"
    ]
  }

  provisioner "shell" {
    inline = [
      "eval $(mise activate)",
      "mise doctor"
    ]
  }

  # provisioner  "shell" {
  #   # Get indico
  #   inline = [
  #     "cd /indico",
  #     # "git clone --branch v3.3.13 --depth 1 --bare https://github.com/indico/indico",
  #     "ls -lhta",
  #     "mise tasks run install"
  #   ]
  # }
  post-processors {
    post-processor "docker-tag" {
      repository = "ghcr.io/hashi-at-home/indico"
      tags = ["latest"]
    }
  }
}
