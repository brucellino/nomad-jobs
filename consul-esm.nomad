

job "consul-esm" {
  group "main" {
    count = 3
    task "monitor" {

      driver = "exec"
      config {
        command = "local/consul-esm"
      }
      artifact {
        source      = "https://releases.hashicorp.com/consul-esm/0.7.1/consul-esm_0.7.1_linux_arm64.zip"
        destination = "local/consul-esm"
        mode        = "file"
      }
      identity {
        env  = true
        file = true
      }

      resources {
        cpu    = 125
        memory = 125
      }
    }
  }
}
