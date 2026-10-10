packer {
  required_plugins {
    docker = {
      source = "github.com/hashicorp/docker"
      version = "~> 1"
    }
  }
}

source "docker" "ubuntu" {
  image = "ubuntu:20.04"
  commit = true
}

build {
  sources = ["source.docker.ubuntu"]
  provisioner "shell" {
    inline = ["echo hi"]
  }
}
