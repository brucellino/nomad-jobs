# Add the csi host path plugin
variable "go_version" {
  type = string
  description = "Version of Go to use for compiling the plugin"
  default = "1.18.8"
}

variable "plugin_version" {
  type = string
  description = "Version of Hostpath csi plugin to use"
  default = "1.9.0"
}



job "plugin-csi-hostpath-controller" {
  datacenters = ["dc1"]
  type = "system"
  group "controller" {
    task "build" {
      artifact {
        source = "https://go.dev/dl/go${var.go_version}.linux-${attr.cpu.arch}.tar.gz"
        destination = "${NOMAD_ALLOC_DIR}/usr/local"
      }
      artifact {
        source = "https://github.com/kubernetes-csi/csi-driver-host-path/archive/refs/tags/v${var.plugin_version}.tar.gz"
        destination = "local/"
      }
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
        PLUGIN_VERSION = var.plugin_version
        PATH = "${NOMAD_ALLOC_DIR}/usr/local/go/bin:${PATH}"
      }
      config {
        command = "local/script.sh"
      }
      template {
        data = <<EOF
#!/bin/bash
set -eou pipefail
cd ${NOMAD_ALLOC_DIR}/local/csi-driver-host-path-${PLUGIN_VERSION}
PATH=${NOMAD_ALLOC_DIR}/usr/local/go/bin:${PATH} install bin/hostpathplugin ${NOMAD_ALLOC_DIR}/bin/
        EOF
        destination = "local/script.sh"
        perms       = "0777"
      }
    }

    task "plugin" {
      resources {
        cpu    = 10 # 10 MHz
        memory = 25 # 25MB
      }
      driver = "exec"
      config {
        command = "${NOMAD_ALLOC_DIR}/hostpathplugin"
        args = [
          "--drivername=csi-hostpath",
          "--v=5",
          "--endpoint=${CSI_ENDPOINT}",
          "--nodeid=node-${NOMAD_ALLOC_INDEX}"
        ]
      }
      csi_plugin {
        id = "csi-hostpath"
        type = "monolith"
        mount_dir = "/data/csi"
      }
    }
  }
}
