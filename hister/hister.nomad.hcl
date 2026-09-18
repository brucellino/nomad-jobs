# Nomad job for hister local search
job "hister" {
  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "amd64"
  }

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "pop-os"
  }

  group "hister" {
    network {
      port "http" {
        static = 4433
      }
    }
    task "server" {
      resources {
        cpu    = 2
        memory = 2048
      }
      template {
        data        = <<EOT
app:
    directory: /local/.config/hister
    title: Hister
    subtitle: Your own search engine
    color_scheme: automatic
    search_url: https://google.com/search?q={query}
    access_token: ""
    user_handling: false
    public: false
    log_level: info
    log_file: ""
    log_format: ""
    debug_sql: false
    open_results_on_new_tab: false
    redirect_on_no_results: true
    display_extractor_config: false
    disable_previews: false
    profiler: false
server:
    address: 0.0.0.0:4433
    base_url: http://{{ env "NOMAD_ADDR_http" }}
    database: db.sqlite3
    max_batch_body_size: 40
    oauth: {}
    oauth_only: false
indexer:
    detect_languages: true
    keep_stopwords: false
    directories: []
    max_file_size_mb: 1
crawler:
    timeout: 5
    delay: 0
    backend: http
    backend_options: {}
    proxy: ""
    user_agent: ""
    headers: {}
    cookies: []
    no_robots: false
semantic_search:
    enable: false
    embedding_endpoint: http://localhost:11434/v1/embeddings
    embedding_model: qwen3-embedding:8b
    embedding_timeout: 300
    api_key: ""
    headers: {}
    dimensions: 2000
    max_context_length: 512
    chunk_overlap: 64
    max_embedding_batch_size: 8
    query_prefix: 'query: '
    document_prefix: ""
    similarity_threshold: 0.1
    result_limit: 50
    semantic_weight: 0.4
    max_embedding_concurrency: 2
hotkeys:
    web:
        /: focus_search_input
        '?': show_hotkeys
        alt+d: delete_result
        alt+enter: open_result_in_new_tab
        alt+j: select_next_result
        alt+k: select_previous_result
        alt+o: open_query_in_search_engine
        alt+v: view_result_popup
        enter: open_result
        tab: autocomplete
sensitive_content_patterns:
    aws_access_key: (^|[\s"'])AKIA[0-9A-Z]{16}([\s"']|$)
    aws_secret_key: (?i)aws(.{0,20})?(secret)?(.{0,20})?['"][0-9a-zA-Z\/+]{40}['"]
    generic_private_key: '-----BEGIN ((RSA|EC|DSA) )?PRIVATE KEY-----'
    github_token: (ghp|gho|ghu|ghs|ghr)_[a-zA-Z0-9]{36}
    pgp_private_key: '-----BEGIN PGP PRIVATE KEY BLOCK-----' #pragma: allowlist secret
    ssh_private_key: '-----BEGIN OPENSSH PRIVATE KEY-----' #pragma: allowlist secret
extractors:
  discourse:
    enable: true
  markdown:
    enable: true
  embeddedvideo:
    enable: true
  github:
    enabled: true
        EOT
        destination = "/local/hister.config.yml"
      }
      driver = "docker"
      config {
        image = "ghcr.io/asciimoo/hister:latest"
        ports = ["http"]
        args  = ["listen", "--config", "/local/hister.config.yml"]
      }
    }
  }
}
