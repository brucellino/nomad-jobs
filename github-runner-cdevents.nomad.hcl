job "runner" {
  type = "batch"
  # Only run on ARM64 machines
  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "arm64"
  }
  # Only run one instance at a time on a host
  constraint {
    distinct_hosts = true
  }


  parameterized {
    meta_required = [
      "github_repository",
      "github_token",
      "github_url",
      "runner_name"
    ]
    meta_optional = [
      "github",
      "github_owner",
      "github_organization",
      "workflow_name",
      "workflow_run_id",
      "workflow_job_id",
      "workflow_job_name",
      "workflow_branch",
      "runner_labels",
      "cdevent_id",
      "cdevent_type",
      "cdevent_timestamp",
    ]
    payload = "optional"
  }
  # vault {}
  group "github" {
    task "runner" {
      resources {
        cpu    = 2000
        memory = 2048
      }
      driver = "exec"
      config {
        command = "/local/runner.sh"
      }
      template {
        data        = <<EOT
#!/bin/bash
set -eo pipefail
mkdir -vp actions-runner
cd actions-runner
curl -o actions-runner-linux-arm64-2.331.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.331.0/actions-runner-linux-arm64-2.331.0.tar.gz
echo "f5863a211241436186723159a111f352f25d5d22711639761ea24c98caef1a9a  actions-runner-linux-arm64-2.331.0.tar.gz" | shasum -a 256 -c
tar xzf ./actions-runner-linux-arm64-2.331.0.tar.gz
RUNNER_ALLOW_RUNASROOT=true ./config.sh \
  --url ${NOMAD_META_github_url} \
  --token ${NOMAD_META_github_token} \
  --ephemeral \
  --unattended \
  --labels ${NOMAD_META_runner_labels} \
  --name ${NOMAD_META_runner_name}
RUNNER_ALLOW_RUNASROOT=true ./run.sh
        EOT
        destination = "${NOMAD_TASK_DIR}/runner.sh"
      }
    }
  }
}
