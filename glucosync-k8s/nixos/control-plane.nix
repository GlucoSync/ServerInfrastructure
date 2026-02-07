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
      6443   # Kubernetes API
      2379   # etcd
      2380   # etcd peer
      10250  # kubelet
      10251  # kube-scheduler
      10252  # kube-controller-manager
    ];
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
    ║                                                              ║
    ╚══════════════════════════════════════════════════════════════╝

    Quick Commands:
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      kubectl get nodes                # Check cluster nodes
      kubectl get pods -A              # Check all pods
      k9s                              # Interactive cluster UI
      /etc/glucosync-scripts/install-components.sh  # Install components

    Join Worker Nodes:
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      cat /root/k3s-join-info.txt

    Kubeconfig:
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

    EOF
  '';
}
