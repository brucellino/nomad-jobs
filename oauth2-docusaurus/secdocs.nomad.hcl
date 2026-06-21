job "secure-docs" {
  group "docusaurus" {
    network {
      port "docs" {
        to = 3000
      }
    }

    service {
      name = "docusaurus"
      port = "docs"
    }
    task "docusaurus" {
      resources {
        cpu    = 2000
        memory = 2048
      }
      driver = "docker"
      config {
        image      = "node:24"
        ports      = ["docs"]
        entrypoint = ["sh", "-c", "npx create-docusaurus@latest -t blog classic . && cd blog && npm install && npm run start -- --host 0.0.0.0 --poll 1000"]
      }
    }
  }
  group "auth-proxy" {
    update {
      max_parallel      = 2
      health_check      = "checks"
      min_healthy_time  = "10s"
      healthy_deadline  = "5m"
      progress_deadline = "10m"
      auto_revert       = true
      auto_promote      = true
      canary            = 1
      stagger           = "20s"
    }
    network {
      port "oauth2" {
        to = 4180
      }
    }

    service {
      name = "oauth2-proxy"
      port = "oauth2"
      # check {
      #   type     = "http"
      #   path     = "/health"
      #   interval = "10s"
      #   timeout  = "2s"
      # }
    }
    task "oauth2-proxy" {
      driver = "docker"
      template {
        data        = <<EOF
{{- range service "keycloak" }}
OAUTH2_PROXY_OIDC_ISSUER_URL="http://{{ .Address }}:{{ .Port }}/realms/myrealm"
OAUTH2_PROXY_REDIRECT_URL="http://localhost/oauth2/callback"
{{- end }}
      EOF
        destination = "/local/.env"
        env         = true
      }
      env {
        OAUTH2_PROXY_PROVIDER         = "keycloak-oidc"
        OAUTH2_PROXY_CLIENT_ID        = "docusaurus"
        OAUTH2_PROXY_CLIENT_SECRET    = ""
        OAUTH2_PROXY_COOKIE_DOMAIN    = "localhost"
        OAUTH2_PROXY_COOKIE_NAME      = "docusaurus_dev_auth"
        OAUTH2_PROXY_COOKIE_SAMESITE  = "lax"
        OAUTH2_PROXY_COOKIE_SECRET    = ""
        OAUTH2_PROXY_COOKIE_SECURE    = "false"
        OAUTH2_PROXY_REVERSE_PROXY    = "true"
        OAUTH2_PROXY_SET_XAUTHREQUEST = "true"
        OAUTH2_PROXY_EMAIL_DOMAINS    = "*"
        OAUTH2_PROXY_WHITELIST_DOMAIN = "service.consul"
      }
      config {
        image   = "quay.io/oauth2-proxy/oauth2-proxy:v7.15.2-alpine"
        command = "--http-address=0.0.0.0:4180"
        ports   = ["oauth2"]
      }
    }
  }

  group "nginx" {
    update {
      max_parallel      = 2
      health_check      = "checks"
      min_healthy_time  = "10s"
      healthy_deadline  = "5m"
      progress_deadline = "10m"
      auto_revert       = true
      auto_promote      = true
      canary            = 1
      stagger           = "20s"
    }
    network {
      port "http" {
        to = 80
      }
    }
    service {
      name = "docs-nginx"
      port = "http"
      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
      }
    }
    task "nginx" {
      driver = "docker"
      env {
        OAUTH2_PROXY_SET_XAUTHREQUEST = true
      }
      config {
        image = "nginx:1.27-alpine"
        volumes = [
          "local/conf.d:/etc/nginx/"
        ]
        ports = ["http"]
      }

      template {
        data        = <<EOF
events {}

http {
    # Conditional Connection header for WebSocket upgrades
    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
    }

    server {
        listen 80;

        location = /health {
          access_log off;
          add_header 'Content-Type' 'application/json';
          return 200 '{"status":"UP"}';
        }

        # Webpack/Vite/DevServer HMR WebSocket endpoints
        # Ensure these take precedence over regex locations below
        location ^~ /ws {
{{- range service "docusaurus" }}
            proxy_pass http://{{ .Address }}:{{ .Port }};
{{- end }}
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_read_timeout 1h;
            proxy_send_timeout 1h;
            proxy_buffering off;
        }

        location ^~ /sockjs-node {
{{- range service "docusaurus" }}
            proxy_pass http://{{ .Address }}:{{ .Port }};
{{- end }}
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_read_timeout 1h;
            proxy_send_timeout 1h;
            proxy_buffering off;
        }

        location / {
{{- range service "docusaurus" }}
            proxy_pass http://{{ .Address }}:{{ .Port }};
{{- end }}
            proxy_http_version 1.1;

            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
        }

        # Protect /redoc + /spec/openapi.yaml with oauth2-proxy
        location ~ ^/(redoc|spec) {
            auth_request /oauth2/auth;
            error_page 401 = @error401;
            error_page 403 = @error401;
{{- range service "docusaurus" }}
            proxy_pass http://{{ .Address }}:{{ .Port }};
{{- end }}

            auth_request_set $auth_user   $upstream_http_x_auth_request_user;
            auth_request_set $auth_email  $upstream_http_x_auth_request_email;
            proxy_set_header X-User  $auth_user;
            proxy_set_header X-Email $auth_email;
        }

        # oauth2-proxy endpoints (login, callback, logout)
        location /oauth2/ {
{{- range service "oauth2-proxy" }}
            proxy_pass       http://{{ .Address }}:{{ .Port }};
{{- end }}
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Auth-Request-Redirect $request_uri;
            proxy_set_header Cookie $http_cookie;
        }

        # oauth2-proxy → internal auth check
        location = /oauth2/auth {
            internal;
{{- range service "oauth2-proxy" }}
            proxy_pass       http://{{ .Address }}:{{ .Port }};
{{- end }}
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-Uri  $request_uri;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Cookie $http_cookie;
            # nginx auth_request includes headers but not body
            proxy_set_header Content-Length   "";
            proxy_pass_request_body           off;
        }

        # Handle unauthenticated users (preserve original URL)
        location @error401 {
            return 302 /oauth2/start?rd=$request_uri;
        }
    }
}
EOF
        destination = "/local/conf.d/nginx.conf"
      }
    }
  }

}
