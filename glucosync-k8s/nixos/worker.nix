{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Hostname (will be overridden per node)
  networking.hostName = "glucosync-worker";

  # Additional packages for workers
  environment.systemPackages = with pkgs; [
    kubectl
    k9s
    docker
  ];

  # Performance tuning for worker nodes
  boot.kernel.sysctl = {
    # Increase connection tracking table size
    "net.netfilter.nf_conntrack_max" = 262144;

    # Optimize for container workloads
    "vm.max_map_count" = 262144;
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 512;
  };

  # Automatic cleanup of old containers
  systemd.services.container-cleanup = {
    description = "Cleanup old containers and images";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "container-cleanup" ''
        #!/usr/bin/env bash
        set -e

        echo "Cleaning up old containers..."
        ${pkgs.docker}/bin/docker system prune -af --volumes --filter "until=168h"

        echo "Cleanup complete"
      ''}";
    };
  };

  systemd.timers.container-cleanup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  # Welcome message
  environment.interactiveShellInit = ''
    cat << 'EOF'

    ╔══════════════════════════════════════════════════════════════╗
    ║                                                              ║
    ║           🔧 GlucoSync Kubernetes Worker Node 🔧             ║
    ║                                                              ║
    ╚══════════════════════════════════════════════════════════════╝

    Node Status:
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      systemctl status k3s             # Check K3s agent status
      docker ps                        # Check running containers
      df -h                            # Check disk space

    EOF
  '';
}
