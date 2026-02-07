{ config, pkgs, lib, ... }:

{
  # Comprehensive security hardening for GlucoSync infrastructure

  # Fail2ban - Intrusion prevention
  services.fail2ban = {
    enable = true;
    maxretry = 3;
    bantime = "1h";
    bantime-increment = {
      enable = true;
      multipliers = "1 2 4 8 16 32 64";
      maxtime = "168h"; # 1 week
      overalljails = true;
    };

    jails = {
      # SSH brute force protection
      sshd = {
        enabled = true;
        settings = {
          mode = "aggressive";
          port = "ssh";
          logpath = "/var/log/auth.log";
          maxretry = 3;
          findtime = "10m";
          bantime = "1h";
        };
      };

      # Kubernetes API server protection
      k3s-api = {
        enabled = true;
        settings = {
          port = "6443";
          logpath = "/var/log/k3s.log";
          maxretry = 5;
          findtime = "5m";
          bantime = "30m";
        };
      };
    };
  };

  # Firewall configuration
  networking.firewall = {
    enable = true;

    # Allow SSH
    allowedTCPPorts = [ 22 ];

    # Rate limiting for SSH
    extraCommands = ''
      # Rate limit SSH connections
      iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set
      iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 -j DROP

      # Drop invalid packets
      iptables -A INPUT -m state --state INVALID -j DROP

      # Allow established connections
      iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

      # Log dropped packets
      iptables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "iptables-dropped: " --log-level 4
    '';
  };

  # AppArmor for additional security
  security.apparmor = {
    enable = true;
    packages = with pkgs; [
      apparmor-profiles
      apparmor-utils
    ];
  };

  # Auditing system calls
  security.auditd.enable = true;
  security.audit = {
    enable = true;
    rules = [
      # Monitor SSH
      "-w /var/log/auth.log -p wa -k auth_log"
      "-w /etc/ssh/sshd_config -p wa -k sshd_config"

      # Monitor user changes
      "-w /etc/passwd -p wa -k passwd_changes"
      "-w /etc/group -p wa -k group_changes"
      "-w /etc/shadow -p wa -k shadow_changes"

      # Monitor sudo usage
      "-w /var/log/sudo.log -p wa -k sudo_log"

      # Monitor network changes
      "-w /etc/network/ -p wa -k network_changes"

      # Monitor cron jobs
      "-w /etc/cron.allow -p wa -k cron_changes"
      "-w /etc/cron.deny -p wa -k cron_changes"
      "-w /etc/crontab -p wa -k cron_changes"

      # Monitor kernel module loading
      "-w /sbin/insmod -p x -k modules"
      "-w /sbin/rmmod -p x -k modules"
      "-w /sbin/modprobe -p x -k modules"
    ];
  };

  # System security limits
  security.pam.loginLimits = [
    { domain = "*"; type = "soft"; item = "nofile"; value = "65536"; }
    { domain = "*"; type = "hard"; item = "nofile"; value = "65536"; }
    { domain = "*"; type = "soft"; item = "nproc"; value = "32768"; }
    { domain = "*"; type = "hard"; item = "nproc"; value = "32768"; }
  ];

  # Disable unnecessary services
  services = {
    # Disable Avahi (mDNS)
    avahi.enable = false;

    # Disable CUPS (printing)
    printing.enable = false;
  };

  # Secure kernel parameters
  boot.kernel.sysctl = {
    # Prevent SYN flood attacks
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.tcp_syn_retries" = 2;
    "net.ipv4.tcp_synack_retries" = 2;
    "net.ipv4.tcp_max_syn_backlog" = 4096;

    # Ignore ICMP redirects
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.secure_redirects" = 0;
    "net.ipv4.conf.default.secure_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;

    # Ignore ICMP ping requests
    "net.ipv4.icmp_echo_ignore_all" = 0; # Set to 1 to ignore pings

    # Log suspicious packets
    "net.ipv4.conf.all.log_martians" = 1;
    "net.ipv4.conf.default.log_martians" = 1;

    # Protect against time-wait assassination
    "net.ipv4.tcp_rfc1337" = 1;

    # Kernel hardening
    "kernel.dmesg_restrict" = 1;
    "kernel.kptr_restrict" = 2;
    "kernel.unprivileged_bpf_disabled" = 1;
    "kernel.unprivileged_userns_clone" = 0;

    # Disable core dumps
    "kernel.core_uses_pid" = 1;
    "fs.suid_dumpable" = 0;
  };

  # Automated security scanning
  systemd.services.security-scan = {
    description = "Daily security vulnerability scan";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "security-scan" ''
        #!/usr/bin/env bash
        set -e

        echo "Running security scan..."

        # Check for failed login attempts
        echo "Failed SSH attempts:"
        ${pkgs.gnugrep}/bin/grep "Failed password" /var/log/auth.log | tail -10 || true

        # Check for sudo usage
        echo "Recent sudo usage:"
        ${pkgs.gnugrep}/bin/grep "sudo:" /var/log/auth.log | tail -10 || true

        # Check listening ports
        echo "Listening ports:"
        ${pkgs.nettools}/bin/netstat -tuln

        # Check for rootkits (if installed)
        if command -v rkhunter &> /dev/null; then
          rkhunter --check --skip-keypress
        fi
      ''}";
    };
  };

  systemd.timers.security-scan = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  # ClamAV antivirus (optional, can be heavy)
  # services.clamav = {
  #   daemon.enable = true;
  #   updater.enable = true;
  # };

  # Rootkit detection
  environment.systemPackages = with pkgs; [
    rkhunter
    chkrootkit
    lynis # Security auditing tool
  ];

  # Regular security audits
  systemd.services.lynis-audit = {
    description = "Weekly security audit with Lynis";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.lynis}/bin/lynis audit system --quick --no-colors";
    };
  };

  systemd.timers.lynis-audit = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
    };
  };


  # System hardening tips logged on login
  environment.interactiveShellInit = ''
    echo "🔒 GlucoSync Security Hardened System"
    echo "======================================"
    echo "Fail2ban: Active"
    echo "AppArmor: Enabled"
    echo "Audit: Running"
    echo "Firewall: Enabled"
    echo ""
    echo "Security commands:"
    echo "  - fail2ban-client status      # Check fail2ban status"
    echo "  - fail2ban-client status sshd # Check SSH jail"
    echo "  - aa-status                   # Check AppArmor status"
    echo "  - auditctl -l                 # List audit rules"
    echo "  - lynis audit system          # Run security audit"
    echo ""
  '';
}
