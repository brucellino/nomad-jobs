# Job to add Ansible to all nodes, in order to allow them to
# configure themselves
job "ansible" {
  type = "sysbatch"
  datacenters = ["dc1"]
  name = "Ansible"
  periodic {
    cron = "@daily"
    enabled = true
  }
  group "nodes" {
    count = 1
    task "step-up" {
      template {
        change_mode = "noop"
        destination = "local/install-ansible.sh"
        perms = "0777"
        data = <<EOT
#!/bin/env bash
echo hi
EOT
      }
      driver = "raw_exec"
      config {
        command = "local/install-ansible.sh"
      }
    }
  }
}
