{ config, pkgs, lib, ... }:

{
  # K3s Agent (Worker Node) Configuration

  services.k3s = {
    enable = true;
    role = "agent";

    # These will be set via environment variables or secrets
    serverAddr = lib.mkDefault "https://CONTROL_PLANE_IP:6443";
    tokenFile = lib.mkDefault "/etc/rancher/k3s/token";

    extraFlags = toString [
      "--node-label node-role.kubernetes.io/worker=true"
    ];

    package = pkgs.k3s;
  };

  # Create token file from environment variable
  system.activationScripts.k3s-token = ''
    mkdir -p /etc/rancher/k3s

    if [ -n "$K3S_TOKEN" ]; then
      echo "$K3S_TOKEN" > /etc/rancher/k3s/token
      chmod 600 /etc/rancher/k3s/token
    fi
  '';

  # Firewall rules for K3s agent
  networking.firewall = {
    allowedTCPPorts = [
      10250  # Kubelet API
      30000-32767  # NodePort range
    ];

    allowedUDPPorts = [
      8472   # Flannel VXLAN
    ];
  };

  # Ensure k3s starts after network is up
  systemd.services.k3s = {
    after = [ "network-online.target" "firewall.service" ];
    wants = [ "network-online.target" ];

    # Environment variables
    environment = {
      K3S_URL = lib.mkDefault "https://CONTROL_PLANE_IP:6443";
    };

    # Read token from file
    serviceConfig = {
      # Increase limits for Kubernetes
      LimitNOFILE = "1048576";
      LimitNPROC = "infinity";
      LimitCORE = "infinity";
      TasksMax = "infinity";

      # Restart policy
      Restart = "always";
      RestartSec = "5s";

      # Read K3S_TOKEN from environment
      EnvironmentFile = lib.mkIf (builtins.pathExists /etc/rancher/k3s/k3s.env) "/etc/rancher/k3s/k3s.env";
    };

    # Pre-start script to check connectivity
    preStart = ''
      # Wait for control plane to be reachable
      timeout 300 bash -c 'until ${pkgs.curl}/bin/curl -k -s https://CONTROL_PLANE_IP:6443 &> /dev/null; do
        echo "Waiting for control plane..."
        sleep 5
      done'
    '';
  };

  # Install kubectl for debugging
  environment.systemPackages = with pkgs; [
    kubectl
    k9s
  ];

  # Health check service
  systemd.services.k3s-health-check = {
    description = "K3s Worker Health Check";
    after = [ "k3s.service" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "k3s-health-check" ''
        #!/usr/bin/env bash
        set -e

        # Check if kubelet is running
        if ${pkgs.systemd}/bin/systemctl is-active k3s; then
          echo "K3s agent is running"

          # Check if node is registered (if kubeconfig available)
          if [ -f /etc/rancher/k3s/k3s.yaml ]; then
            export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
            ${pkgs.kubectl}/bin/kubectl get node $(hostname)
          fi
        else
          echo "K3s agent is not running!"
          exit 1
        fi
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

  # Monitor disk space (important for container storage)
  systemd.services.disk-space-monitor = {
    description = "Monitor disk space for container storage";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "disk-space-monitor" ''
        #!/usr/bin/env bash

        # Check disk usage
        USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')

        if [ $USAGE -gt 85 ]; then
          echo "WARNING: Disk usage is at $USAGE%"

          # Clean up Docker images
          ${pkgs.docker}/bin/docker system prune -af --volumes || true

          # Clean up Kubernetes
          ${pkgs.kubectl}/bin/kubectl delete pods --field-selector=status.phase=Failed -A || true
          ${pkgs.kubectl}/bin/kubectl delete pods --field-selector=status.phase=Succeeded -A || true
        fi
      ''}";
    };
  };

  systemd.timers.disk-space-monitor = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };
}
