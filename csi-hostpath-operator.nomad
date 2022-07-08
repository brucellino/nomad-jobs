job "csi" {
  datacenters = ["dc1"]
  type = "sysbatch"
  group "hostpath" {
    task "install" {
      driver = "raw_exec"
        config {
          command = "local/script.sh"
        }
      template {
        data = <<EOF
#!/bin/bash
set -eou pipefail
sudo apt-get install -y golang
git clone https://github.com/kubernetes-csi/csi-driver-host-path.git
cd csi-driver-host-path
sudo make
sudo install bin/hostpathplugin /usr/local/bin/
        EOF
        destination = "local/script.sh"
        perms = "0777"
      }
    }
  }
}
