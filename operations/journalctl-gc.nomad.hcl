job "journalctl-gc" {
  datacenters = ["dc1"]
  type        = "sysbatch"
  region      = "global"
  namespace   = "ops"

  periodic {
    crons            = ["@daily"]
    prohibit_overlap = true
  }


  group "garbage-collection" {
    task "garbage-collection" {
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
  }
}
