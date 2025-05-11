job "journalctl-gc" {
  datacenters = ["dc1"]
  type        = "sysbatch"
  region      = "global"
  namespace   = "ops"
  priority    = 100

  periodic {
    crons            = ["@daily"]
    prohibit_overlap = true
  }


  group "garbage-collection" {
    task "journalctl" {
      resources {
        memory = 64
        cpu    = 100
      }
      driver = "raw_exec"

      config {
        command = "journalctl"
        args    = ["--vacuum-time", "7d"]
      }
    }
    task "docker" {
      resources {
        memory = 64
        cpu    = 100
      }
      driver = "raw_exec"
      config {
        command = "docker"
        args    = ["system", "prune", "--volumes", "--force"]
      }
    }
  }
}
