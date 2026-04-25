job "secure-docs" {
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
        # location ^~ /ws {
        #     proxy_pass http://docusaurus:3000;
        #     proxy_http_version 1.1;
        #     proxy_set_header Upgrade $http_upgrade;
        #     proxy_set_header Connection $connection_upgrade;
        #     proxy_set_header Host $host;
        #     proxy_set_header X-Real-IP $remote_addr;
        #     proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        #     proxy_set_header X-Forwarded-Proto $scheme;
        #     proxy_set_header X-Forwarded-Host $host;
        #     proxy_read_timeout 1h;
        #     proxy_send_timeout 1h;
        #     proxy_buffering off;
        # }

        # location ^~ /sockjs-node {
        #     proxy_pass http://docusaurus:3000;
        #     proxy_http_version 1.1;
        #     proxy_set_header Upgrade $http_upgrade;
        #     proxy_set_header Connection $connection_upgrade;
        #     proxy_set_header Host $host;
        #     proxy_set_header X-Real-IP $remote_addr;
        #     proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        #     proxy_set_header X-Forwarded-Proto $scheme;
        #     proxy_set_header X-Forwarded-Host $host;
        #     proxy_read_timeout 1h;
        #     proxy_send_timeout 1h;
        #     proxy_buffering off;
        # }

        # location / {
        #     proxy_pass http://docusaurus:3000;
        #     proxy_http_version 1.1;

        #     proxy_set_header Host $host;
        #     proxy_set_header X-Real-IP $remote_addr;
        #     proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        #     proxy_set_header X-Forwarded-Proto $scheme;
        #     proxy_set_header X-Forwarded-Host $host;
        # }

        # Protect /redoc + /spec/openapi.yaml with oauth2-proxy
        # location ~ ^/(redoc|spec) {
        #     auth_request /oauth2/auth;
        #     error_page 401 = @error401;
        #     error_page 403 = @error401;
        #     proxy_pass http://docusaurus:3000;

        #     auth_request_set $auth_user   $upstream_http_x_auth_request_user;
        #     auth_request_set $auth_email  $upstream_http_x_auth_request_email;
        #     proxy_set_header X-User  $auth_user;
        #     proxy_set_header X-Email $auth_email;
        # }

        # # oauth2-proxy endpoints (login, callback, logout)
        # location /oauth2/ {
        #     proxy_pass       http://oauth2-proxy:4180;
        #     proxy_set_header Host $host;
        #     proxy_set_header X-Real-IP $remote_addr;
        #     proxy_set_header X-Auth-Request-Redirect $request_uri;
        #     proxy_set_header Cookie $http_cookie;
        # }

        # # oauth2-proxy → internal auth check
        # location = /oauth2/auth {
        #     internal;
        #     proxy_pass       http://oauth2-proxy:4180;
        #     proxy_set_header Host $host;
        #     proxy_set_header X-Real-IP $remote_addr;
        #     proxy_set_header X-Forwarded-Uri  $request_uri;
        #     proxy_set_header X-Forwarded-Host $host;
        #     proxy_set_header X-Forwarded-Proto $scheme;
        #     proxy_set_header Cookie $http_cookie;
        #     # nginx auth_request includes headers but not body
        #     proxy_set_header Content-Length   "";
        #     proxy_pass_request_body           off;
        # }

        # # Handle unauthenticated users (preserve original URL)
        # location @error401 {
        #     return 302 /oauth2/start?rd=$request_uri;
        # }
    }
}
EOF
        destination = "/local/conf.d/nginx.conf"
      }
    }
  }

}
