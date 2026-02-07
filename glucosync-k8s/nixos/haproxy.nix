{ config, pkgs, lib, ... }:

# ⚠️  DEPRECATED: This standalone HAProxy configuration is no longer used.
# HAProxy is now integrated into the control plane configuration.
# See: ./control-plane.nix
#
# This file is kept for reference only.

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Hostname
  networking.hostName = "glucosync-haproxy";

  # HAProxy service
  services.haproxy = {
    enable = true;

    config = ''
      global
          log /dev/log local0
          log /dev/log local1 notice
          chroot /var/lib/haproxy
          stats socket /run/haproxy/admin.sock mode 660 level admin
          stats timeout 30s
          user haproxy
          group haproxy
          daemon

          # SSL/TLS settings
          ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
          ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets
          ssl-default-server-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
          ssl-default-server-options ssl-min-ver TLSv1.2 no-tls-tickets

          # Performance tuning
          maxconn 40000
          tune.ssl.default-dh-param 2048
          nbthread 4

      defaults
          log     global
          mode    http
          option  httplog
          option  dontlognull
          option  http-server-close
          option  forwardfor except 127.0.0.0/8
          option  redispatch
          retries 3
          timeout connect 5000
          timeout client  50000
          timeout server  50000
          timeout http-request 10s
          timeout http-keep-alive 10s
          timeout queue 30s

      # Statistics page
      frontend stats
          bind *:8404
          mode http
          stats enable
          stats uri /stats
          stats refresh 10s
          stats admin if TRUE

      # HTTP frontend (redirect to HTTPS)
      frontend http_front
          bind *:80
          mode http
          redirect scheme https code 301 if !{ ssl_fc }

      # HTTPS frontend
      frontend https_front
          bind *:443
          mode tcp
          option tcplog

          # Route to Nginx Ingress on worker nodes
          default_backend k8s_nginx_ingress

      # Kubernetes Nginx Ingress backend
      backend k8s_nginx_ingress
          mode tcp
          balance roundrobin
          option tcp-check

          # Worker nodes (UPDATE WITH ACTUAL IPs)
          server worker1 WORKER1_IP:30443 check
          server worker2 WORKER2_IP:30443 check
          server worker3 WORKER3_IP:30443 check

      # TCP passthrough for Kubernetes API
      frontend tcp_k8s_api
          bind *:6443
          mode tcp
          option tcplog
          default_backend k8s_api_servers

      backend k8s_api_servers
          mode tcp
          balance roundrobin
          option tcp-check
          server controlplane CONTROLPLANE_IP:6443 check
    '';
  };

  # Firewall rules
  networking.firewall = {
    allowedTCPPorts = [
      80    # HTTP (redirects to HTTPS)
      443   # HTTPS
      6443  # Kubernetes API
      8404  # HAProxy stats
    ];
  };

  # Install monitoring tools
  environment.systemPackages = with pkgs; [
    htop
    iftop
    nettools
    curl
    jq
  ];

  # HAProxy monitoring
  systemd.services.haproxy-monitor = {
    description = "HAProxy health monitoring";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "haproxy-monitor" ''
        #!/usr/bin/env bash

        # Check HAProxy stats
        echo "HAProxy Status:"
        echo "haproxy.sock" | ${pkgs.socat}/bin/socat unix-connect:/run/haproxy/admin.sock stdio || true

        # Check backend health
        ${pkgs.curl}/bin/curl -s http://localhost:8404/stats || true
      ''}";
    };
  };

  systemd.timers.haproxy-monitor = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "minutely";
      Persistent = true;
    };
  };

  # Welcome message
  environment.interactiveShellInit = ''
    cat << 'EOF'

    ╔══════════════════════════════════════════════════════════════╗
    ║                                                              ║
    ║           ⚖️  GlucoSync HAProxy Load Balancer ⚖️             ║
    ║                                                              ║
    ╚══════════════════════════════════════════════════════════════╝

    HAProxy Commands:
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      systemctl status haproxy         # Check HAProxy status
      journalctl -u haproxy -f         # View HAProxy logs
      curl http://localhost:8404/stats # View stats

    Stats Page:
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      http://$(hostname -I | awk '{print $1}'):8404/stats

    EOF
  '';
}
