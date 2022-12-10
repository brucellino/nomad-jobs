variable "doregion" {
  description = "Name of the Digital Ocean region we're using"
  default     = "ams3"
  type        = string
}

variable "loki_version" {
  description = "Version of Grafana Loki to deploy. See "
  type = string
  default = "v2.7.1"
}
