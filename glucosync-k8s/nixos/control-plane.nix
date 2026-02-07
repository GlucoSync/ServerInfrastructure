{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Hostname
  networking.hostName = "glucosync-control-plane";

  # Additional firewall rules for control plane
  networking.firewall = {
    allowedTCPPorts = [
      80     # HTTP (HAProxy - redirects to HTTPS)
      443    # HTTPS (HAProxy)
      6443   # Kubernetes API
      8404   # HAProxy stats
      2379   # etcd
      2380   # etcd peer
      10250  # kubelet
      10251  # kube-scheduler
      10252  # kube-controller-manager
    ];
  };

  # HAProxy load balancer on control plane
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

          # Route to Nginx Ingress (workers or local)
          default_backend k8s_nginx_ingress

      # Kubernetes Nginx Ingress backend
      backend k8s_nginx_ingress
          mode tcp
          balance roundrobin
          option tcp-check

          # Local ingress controller (when running without workers)
          server controlplane 127.0.0.1:30443 check

          # Worker nodes (will be added if they exist)
          # server worker1 WORKER1_IP:30443 check
          # server worker2 WORKER2_IP:30443 check
          # server worker3 WORKER3_IP:30443 check

      # TCP passthrough for Kubernetes API (external access)
      frontend tcp_k8s_api
          bind *:6443
          mode tcp
          option tcplog
          default_backend k8s_api_local

      backend k8s_api_local
          mode tcp
          server controlplane 127.0.0.1:6444 check
    '';
  };

  # HAProxy monitoring
  systemd.services.haproxy-monitor = {
    description = "HAProxy health monitoring";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "haproxy-monitor" ''
        #!/usr/bin/env bash

        # Check HAProxy stats
        echo "HAProxy Status:"
        echo "show stat" | ${pkgs.socat}/bin/socat unix-connect:/run/haproxy/admin.sock stdio || true

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

  # Install infrastructure management tools
  environment.systemPackages = with pkgs; [
    # Kubernetes management
    kubectl
    kubernetes-helm
    k9s
    kubectx
    kustomize
    kubeseal

    # GitOps
    argocd

    # Backup
    velero

    # Monitoring
    prometheus
    grafana

    # MinIO client
    minio-client

    # HAProxy management
    socat

    # Development
    git
    jq
    yq-go
  ];

  # Create helper scripts
  environment.etc."glucosync-scripts/install-components.sh" = {
    text = ''
      #!/usr/bin/env bash
      set -e

      export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

      echo "🚀 Installing GlucoSync Kubernetes Components"
      echo "=============================================="

      # Wait for cluster to be ready
      timeout 120 bash -c 'until kubectl cluster-info &> /dev/null; do sleep 2; done'

      echo "✅ Cluster is ready"

      # Install cert-manager
      echo "📦 Installing cert-manager..."
      kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
      kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s

      # Install Nginx Ingress
      echo "📦 Installing Nginx Ingress Controller..."
      helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
      helm repo update
      helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx --create-namespace \
        --set controller.service.type=NodePort \
        --set controller.service.nodePorts.http=30080 \
        --set controller.service.nodePorts.https=30443

      # Install Longhorn
      echo "📦 Installing Longhorn storage..."
      kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.5.3/deploy/longhorn.yaml

      # Install Zalando Postgres Operator
      echo "📦 Installing Postgres Operator..."
      kubectl apply -k github.com/zalando/postgres-operator/manifests

      # Install Prometheus Operator
      echo "📦 Installing Prometheus Operator..."
      helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
      helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace glucosync-monitoring --create-namespace

      # Install ArgoCD
      echo "📦 Installing ArgoCD..."
      kubectl create namespace argocd || true
      kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

      # Install Sealed Secrets
      echo "📦 Installing Sealed Secrets..."
      kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

      # Apply namespaces
      echo "📦 Creating GlucoSync namespaces..."
      kubectl apply -f /etc/glucosync-k8s/k8s/base/namespaces/namespaces.yaml

      echo ""
      echo "✅ All components installed successfully!"
      echo ""
      echo "Get ArgoCD admin password:"
      echo "  kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
      echo ""
      echo "Access services:"
      echo "  Longhorn UI: https://longhorn.glucosync.io"
      echo "  ArgoCD UI: https://argocd.glucosync.io"
      echo "  Grafana UI: https://grafana.glucosync.io"
    '';
    mode = "0755";
  };

  # Copy k8s manifests to /etc
  environment.etc."glucosync-k8s".source = ../k8s;

  # Welcome message
  environment.interactiveShellInit = ''
    cat << 'EOF'

    ╔══════════════════════════════════════════════════════════════╗
    ║                                                              ║
    ║         🚀 GlucoSync Kubernetes Control Plane 🚀             ║
    ║                 (with integrated HAProxy)                    ║
    ║                                                              ║
    ╚══════════════════════════════════════════════════════════════╝

    Quick Commands:
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      kubectl get nodes                # Check cluster nodes
      kubectl get pods -A              # Check all pods
      k9s                              # Interactive cluster UI
      /etc/glucosync-scripts/install-components.sh  # Install components

    HAProxy:
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      systemctl status haproxy         # Check HAProxy status
      journalctl -u haproxy -f         # View HAProxy logs
      curl http://localhost:8404/stats # View stats page

    Join Worker Nodes:
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      cat /root/k3s-join-info.txt

    Kubeconfig:
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

    EOF
  '';
}
