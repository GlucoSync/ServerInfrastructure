{ config, pkgs, lib, ... }:

{
  # K3s Server (Control Plane) Configuration

  services.k3s = {
    enable = true;
    role = "server";

    extraFlags = toString [
      "--disable traefik"           # We use Nginx Ingress
      "--disable servicelb"         # We use MetalLB
      "--write-kubeconfig-mode 644" # Make kubeconfig readable
      "--cluster-init"              # Enable embedded etcd
      "--tls-san $(hostname -I | awk '{print $1}')" # Add node IP to TLS SANs
    ];

    # K3s runs as root
    package = pkgs.k3s;
  };

  # Firewall rules for K3s server
  networking.firewall = {
    allowedTCPPorts = [
      6443   # Kubernetes API server
      10250  # Kubelet API
      2379   # etcd client
      2380   # etcd peer
    ];

    allowedUDPPorts = [
      8472   # Flannel VXLAN
    ];
  };

  # Ensure k3s starts after network is up
  systemd.services.k3s = {
    after = [ "network-online.target" "firewall.service" ];
    wants = [ "network-online.target" ];

    environment = {
      K3S_KUBECONFIG_MODE = "644";
    };

    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
    };
  };

  # Create kubeconfig symlink for easy access
  system.activationScripts.k3s-kubeconfig = ''
    mkdir -p /root/.kube
    mkdir -p /home/afonso/.kube

    if [ -f /etc/rancher/k3s/k3s.yaml ]; then
      ln -sf /etc/rancher/k3s/k3s.yaml /root/.kube/config
      cp /etc/rancher/k3s/k3s.yaml /home/afonso/.kube/config
      chown afonso:users /home/afonso/.kube/config
    fi
  '';

  # Install additional Kubernetes tools
  environment.systemPackages = with pkgs; [
    kubectl
    kubernetes-helm
    k9s
    kubectx
    kustomize
    kubeseal
    velero
    argocd
  ];

  # Add kubectl aliases and completion
  environment.shellAliases = {
    k = "kubectl";
    kgp = "kubectl get pods";
    kgs = "kubectl get svc";
    kgn = "kubectl get nodes";
    kgi = "kubectl get ingress";
    kd = "kubectl describe";
    kl = "kubectl logs";
    kx = "kubectl exec -it";
  };

  # Bash completion for kubectl
  programs.bash.completion.enable = true;
  environment.interactiveShellInit = ''
    source <(kubectl completion bash)
    complete -F __start_kubectl k
  '';

  # Store K3s token for workers to join
  systemd.services.save-k3s-token = {
    description = "Save K3s token for worker nodes";
    after = [ "k3s.service" ];
    wants = [ "k3s.service" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "save-k3s-token" ''
        #!/usr/bin/env bash
        set -e

        # Wait for k3s to be ready
        sleep 10

        if [ -f /var/lib/rancher/k3s/server/node-token ]; then
          TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)
          IP=$(hostname -I | awk '{print $1}')

          echo "================================================"
          echo "K3s Control Plane Ready!"
          echo "================================================"
          echo "Token: $TOKEN"
          echo "URL: https://$IP:6443"
          echo ""
          echo "To join worker nodes, set these environment variables:"
          echo "  export K3S_URL=https://$IP:6443"
          echo "  export K3S_TOKEN=$TOKEN"
          echo "================================================"

          # Save to file for easy access
          cat > /root/k3s-join-info.txt <<EOF
K3s Control Plane Join Information
===================================
K3S_URL=https://$IP:6443
K3S_TOKEN=$TOKEN

To join a worker node:
  export K3S_URL=https://$IP:6443
  export K3S_TOKEN=$TOKEN

Then deploy with:
  nix run .#deploy-worker
EOF

          chmod 600 /root/k3s-join-info.txt
        fi
      ''}";
    };
  };

  systemd.timers.save-k3s-token = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "5m";
    };
  };

  # Health check service
  systemd.services.k3s-health-check = {
    description = "K3s Health Check";
    after = [ "k3s.service" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "k3s-health-check" ''
        #!/usr/bin/env bash
        set -e

        export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

        # Wait for API server
        timeout 60 bash -c 'until ${pkgs.kubectl}/bin/kubectl cluster-info &> /dev/null; do sleep 1; done'

        # Check nodes
        ${pkgs.kubectl}/bin/kubectl get nodes

        # Check system pods
        ${pkgs.kubectl}/bin/kubectl get pods -n kube-system

        echo "K3s cluster is healthy!"
      ''}";
    };
  };

  systemd.timers.k3s-health-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "10m";
    };
  };

  # Automatic backup of etcd
  systemd.services.k3s-etcd-backup = {
    description = "Backup K3s etcd database";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "k3s-etcd-backup" ''
        #!/usr/bin/env bash
        set -e

        BACKUP_DIR="/var/backups/k3s-etcd"
        mkdir -p $BACKUP_DIR

        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        BACKUP_FILE="$BACKUP_DIR/etcd-backup-$TIMESTAMP.tar.gz"

        # Backup etcd data
        tar -czf $BACKUP_FILE /var/lib/rancher/k3s/server/db/

        echo "etcd backup saved to $BACKUP_FILE"

        # Keep only last 7 backups
        ls -t $BACKUP_DIR/etcd-backup-*.tar.gz | tail -n +8 | xargs -r rm
      ''}";
    };
  };

  systemd.timers.k3s-etcd-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };
}
