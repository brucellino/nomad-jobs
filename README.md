# Hashi at Home Nomad jobs

These are the Nomad jobs for [Hashi@Home](https://hashiatho.me)

Many of them are inspired by the works of others, including the Hashicorp Nomad tutorials themselves, so I make no claim over their authorship.

These are not quite ready for production.

## Hashi Stack integration

Hashi@Home is a playground of mostly Raspberry Pis created so that I could experiment and learn the Hashicorp Stack (Vault, Consul, Nomad) and perfect my usage of their tools (Terraform, Packer, Waypoint, _etc_.).
Since the clients in the cluster are mixed architecture, the jobs use constraints or dynamic statements to retrieve relevant artifacts.

### Consul and Vault

Several of the jobs use templates with either Consul or Vault functions.
Consul functions include either lookups in the Consul catalogue, of services or nodes, or template configuration files based on Consul KV data.
The Nomad services and clients are configured to use Nomad workload identities, in order to issue Vault tokens to jobs so that they can consume secrets.

### Terraform

In cases where jobs required backing services outside of the cluster, they are implemented with Terraform.
Terraform is responsible for the creation of the backing resources (DNS entries, S3 buckets, _etc_), as well as the actual Nomad job.
This is especially useful when needing to template Nomad job descriptions, and is used in these cases as a kind of replacement for Nomad Pack.
In these cases, the Terraform backend used is typically Consul, for the reasons provided above.

## Using

You will need a working Nomad cluster of course, which is sufficient for many of the jobs described here.
However, as mentioned above the jobs that required service discovery or interaction with Consul or Vault for templating will of course require those services.
If your cluster has ACLs enabled, you will need to set the `NOMAD_TOKEN` appropriately.

## Jobs

Jobs are found in the main directory, and are mostly schedulable via Nomad itself, using the usual `nomad plan/apply`, while a select few are deployed with Terraform directly.
A few notable examples are described in a bit more depth below:

* [Container Storage Interface](csi/README.md) - attempts to deploy CSI plugins
* [jenkins](jenkins/README.md) - Jenkins controller with configuration as code
* [loki](loki/README.md) - Grafana Loki deployment with DigitalOcean spaces storage
* [monitoring](monitoring/README.md) - unified Grafana monitoring stack (Prometheus, loki, grafana, promtail, node-exporter)
