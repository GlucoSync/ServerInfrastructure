{ config, pkgs, lib, ... }:

{
  # System-wide configuration common to all nodes

  # Nix settings
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      trusted-users = [ "root" "@wheel" ];
    };

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  # Boot loader
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda"; # Change based on your disk

  # Networking
  networking = {
    firewall.enable = true;
    nameservers = [ "1.1.1.1" "8.8.8.8" ];

    # Enable IPv4 forwarding for Kubernetes
    firewall.extraCommands = ''
      iptables -A FORWARD -j ACCEPT
    '';
  };

  # Time zone and locale
  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  # SSH Configuration (hardened)
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
      MaxAuthTries = 3;
      ClientAliveInterval = 300;
      ClientAliveCountMax = 2;
    };

    # Only allow SSH key authentication
    extraConfig = ''
      AllowUsers afonso
      PubkeyAuthentication yes
    '';
  };

  # User configuration
  users = {
    mutableUsers = false;

    users.afonso = {
      isNormalUser = true;
      extraGroups = [ "wheel" "docker" "systemd-journal" ];

      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKsuV7znGPzAetFbhPMYXkxErmn1NJpdTVoFIO5ngZH/ afonso@arka"
      ];

      # Allow passwordless sudo
      hashedPassword = null;
    };

    users.root = {
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKsuV7znGPzAetFbhPMYXkxErmn1NJpdTVoFIO5ngZH/ afonso@arka"
      ];
    };
  };

  # Sudo configuration
  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  # System packages available on all nodes
  environment.systemPackages = with pkgs; [
    # System utilities
    vim
    git
    wget
    curl
    htop
    iotop
    iftop
    tmux
    screen

    # Network tools
    nettools
    inetutils
    nmap
    tcpdump
    mtr

    # Disk utilities
    parted
    gptfdisk

    # Monitoring
    sysstat
    lm_sensors

    # Container tools
    docker
    docker-compose

    # Kubernetes tools
    kubectl
    kubernetes-helm
    k9s

    # File utilities
    unzip
    gzip
    bzip2
    xz

    # Text processing
    jq
    yq-go

    # Development
    gnumake
    gcc
  ];

  # Enable Docker
  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  # System hardening
  boot.kernel.sysctl = {
    # Network security
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.tcp_syncookies" = 1;

    # Kubernetes requirements
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;

    # Performance tuning
    "vm.swappiness" = 10;
    "fs.file-max" = 2097152;
    "net.core.somaxconn" = 32768;
  };

  # Kernel modules for Kubernetes
  boot.kernelModules = [ "br_netfilter" "overlay" ];

  # Automatic updates
  system.autoUpgrade = {
    enable = true;
    dates = "weekly";
    allowReboot = false;
    flake = "github:yourusername/glucosync-k8s";
  };

  # Logging
  services.journald.extraConfig = ''
    SystemMaxUse=1G
    MaxRetentionSec=7day
  '';

  # NTP for time synchronization
  services.timesyncd.enable = true;

  # State version
  system.stateVersion = "23.11";
}
