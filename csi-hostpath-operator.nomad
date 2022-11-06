variable "go_version" {
  type = string
  description = "Version of Go to use for compiling the plugin"
  default = "1.18.8"
}
job "csi" {
  datacenters = ["dc1"]
  type        = "sysbatch"
  group "hostpath" {
    task "go19" {
      resources {
        cpu = 100
        memory = 100
      }
      driver = "exec"
      lifecycle {
        hook = "prestart"
      }
      env {
        ARCH = attr.cpu.arch
        GO_VERSION = var.go_version
        PATH = "${NOMAD_ALLOC_DIR}/usr/local/go/bin:${PATH}"
      }
      config {
        command = "local/script.sh"
      }
      template {
        data = <<EOF
#!/bin/bash
set -eou pipefail
mkdir -vp ${NOMAD_ALLOC_DIR}/usr/local
echo "${ARCH}"
curl -fL https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz | tar xvz -C ${NOMAD_ALLOC_DIR}/usr/local
ls -lht ${NOMAD_ALLOC_DIR}/usr/local/go
        EOF
        destination = "local/script.sh"
        perms       = "0777"
      }
    }
    task "install" {
      driver = "raw_exec"
      resources {
        cpu = 100
        memory = 100
      }
      config {
        command = "local/script.sh"
      }

      template {
        data = <<EOF
#!/bin/bash
set -eou pipefail
go version
git clone https://github.com/kubernetes-csi/csi-driver-host-path.git
cd csi-driver-host-path
PATH=${NOMAD_ALLOC_DIR}/usr/local/go/bin:${PATH} make
sudo PATH=${NOMAD_ALLOC_DIR}/usr/local/go/bin:${PATH} install bin/hostpathplugin /usr/local/bin/
        EOF
        destination = "local/script.sh"
        perms       = "0777"
      }
    }
  }
}
