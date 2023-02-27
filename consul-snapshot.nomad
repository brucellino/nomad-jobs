job "consul-backup" {
  datacenters = ["dc1"]
  type = "batch"
  periodic {
    cron = "1-59/5 * * * * *"
  }
  group "data" {
    count = 1
    network {}
    // volume "scratch" {
    //   type = "host"
    //   source = "scratch"
    //   read_only = false
    // }
    task "get-terraform" {
      driver = "exec"
    lifecycle {
        hook = "prestart"
        sidecar = false
      }
      config {
        command = "bash"
        args = ["-c", "curl https://r1eleases.hashicorp.com/terraform/1.3.4/terraform_1.3.4_linux_arm64.zip | gunzip ->terraform ; chmod u+x terraform"]
      }
      // volume_mount {
      //   volume = "scratch"
      //   destination = "/volume"
      //   read_only = false
      // }
    }
    task "check-consul" {
      driver = "exec"
      config {
        command = "bash"
        args = ["-c", "consul -version"]
      }
    }
  }
}
