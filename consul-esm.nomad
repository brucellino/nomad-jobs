variable "consul_esm_version" {
  type    = string
  default = "0.7.1"
}

job "consul-esm" {
  group "main" {
    count = 3
    task "monitor" {

      driver = "exec"
      config {
        command = "local/consul-esm"
      }
      artifact {
        source      = "https://releases.hashicorp.com/consul-esm/${var.consul_esm_version}/consul-esm_${var.consul_esm_version}_linux_arm64.zip"
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
