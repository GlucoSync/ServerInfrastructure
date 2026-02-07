# GlucoSync Security & Cluster Setup Guide

## Overview

This guide covers the complete security-hardened setup of the GlucoSync Kubernetes cluster. The setup script has been enhanced with comprehensive security measures to protect your infrastructure.

## Prerequisites

- Ubuntu Server 20.04 or 22.04
- Root access
- At least 2 CPU cores and 4GB RAM per node
- Static IP address configured

## Quick Start

```bash
cd glucosync-k8s/scripts
sudo ./cluster-setup.sh
# Select option 9 for full setup with security hardening
```

## Setup Options

The setup script provides the following options:

```
0. Harden System Security (Run First!)
1. Install K3s Control Plane
2. Install K3s Worker Node
3. Install Longhorn Storage
4. Install cert-manager
5. Install Nginx Ingress Controller
6. Create Namespaces
7. Install Postgres Operator
8. Create Secrets
9. Full Setup (Security + Control Plane)
10. Exit
```

## Security Hardening Features

### 1. Automatic Security Updates

- **unattended-upgrades**: Automatic security patches
- **Configuration**: `/etc/apt/apt.conf.d/50unattended-upgrades`
- **Schedule**: Daily updates with automatic kernel cleanup

### 2. SSH Hardening

**Configuration**: `/etc/ssh/sshd_config`

- Root login: Only with SSH keys (no password)
- Password authentication: Disabled
- Maximum authentication attempts: 3
- X11 forwarding: Disabled
- TCP forwarding: Disabled
- Agent forwarding: Disabled
- Verbose logging enabled

### 3. Fail2Ban Intrusion Prevention

**Configuration**: `/etc/fail2ban/jail.local`

**Active Jails**:
- SSH: Ban after 3 failed attempts (1 hour)
- SSH DDoS: Ban after 6 rapid attempts
- K3s API: Ban after 5 failed attempts (30 min)

**Check Status**:
```bash
fail2ban-client status
fail2ban-client status sshd
```

### 4. UFW Firewall

**Default Policies**:
- Incoming: DENY
- Outgoing: ALLOW

**Control Plane Ports**:
- 22: SSH (rate limited)
- 80: HTTP
- 443: HTTPS
- 6443: K3s API Server
- 2379-2380: etcd
- 10250-10252: Kubernetes components
- 8472: Flannel VXLAN (UDP)
- 51820-51821: Flannel WireGuard (UDP)

**Worker Node Ports**:
- 22: SSH (rate limited)
- 10250: Kubelet API
- 8472: Flannel VXLAN (UDP)
- 51820-51821: Flannel WireGuard (UDP)

**Check Status**:
```bash
ufw status numbered
```

### 5. Kernel Security Parameters

**Configuration**: `/etc/sysctl.d/99-glucosync-security.conf`

**Key Settings**:
- IP forwarding enabled (required for Kubernetes)
- ICMP redirect protection
- Source routing disabled
- SYN flood protection
- Martian packet logging
- Time-wait assassination protection
- Kernel pointer restrictions
- BPF restrictions for unprivileged users
- Core dumps disabled

**Reload Settings**:
```bash
sysctl -p /etc/sysctl.d/99-glucosync-security.conf
```

### 6. System Auditing

**Configuration**: `/etc/audit/rules.d/glucosync.rules`

**Monitored Events**:
- Authentication attempts
- SSH configuration changes
- User/group/password modifications
- Sudoers changes
- Network configuration changes
- K3s configuration and data changes
- Cron job modifications
- Kernel module loading

**Check Audit Rules**:
```bash
auditctl -l
```

**View Audit Logs**:
```bash
ausearch -k auth_log
ausearch -k sshd_config
```

### 7. AppArmor Mandatory Access Control

- Enabled by default
- Additional security profiles installed
- Restricts application capabilities

**Check Status**:
```bash
aa-status
```

### 8. AIDE File Integrity Monitoring

- Database initialized on first run
- Daily integrity checks via cron

**Manual Integrity Check**:
```bash
aide --check
```

**Update Database After Legitimate Changes**:
```bash
aide --update
mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
```

### 9. Security Scanning & Monitoring

**Daily Security Scan**:
- Location: `/usr/local/bin/glucosync-security-scan.sh`
- Runs: Daily via cron
- Logs: `/var/log/glucosync-security.log`

**Manual Scan**:
```bash
/usr/local/bin/glucosync-security-scan.sh
```

**Lynis Security Audit**:
```bash
lynis audit system
```

### 10. Security Limits

**Configuration**: `/etc/security/limits.conf`

- File descriptors: 65536
- Processes: 32768
- Optimized for Kubernetes workloads

### 11. Disabled Services

The following unnecessary services are disabled:
- Avahi (mDNS)
- CUPS (printing)
- Bluetooth

## Installation Steps

### Control Plane Setup

```bash
# 1. Transfer the script to your server
scp -r glucosync-k8s user@your-server:~

# 2. SSH into your server
ssh user@your-server

# 3. Run the setup script
cd glucosync-k8s/scripts
sudo ./cluster-setup.sh

# 4. Select option 9 for full setup
# This will:
# - Harden system security
# - Install K3s control plane
# - Create namespaces
# - Install Longhorn storage
# - Install cert-manager
# - Install Nginx Ingress
# - Install Postgres Operator
# - Create secrets (interactive)
```

**Important**: Save the K3s token and URL displayed after installation!

### Worker Node Setup

On each worker node:

```bash
# 1. Transfer the script
scp -r glucosync-k8s user@worker-node:~

# 2. SSH into worker
ssh user@worker-node

# 3. Run security hardening
cd glucosync-k8s/scripts
sudo ./cluster-setup.sh
# Select option 0 to harden security

# 4. Set environment variables from control plane
export K3S_URL="https://control-plane-ip:6443"
export K3S_TOKEN="your-token-here"

# 5. Install worker
sudo ./cluster-setup.sh
# Select option 2 to install worker
```

## Post-Installation

### Verify Cluster

```bash
kubectl get nodes
kubectl get pods -A
kubectl get namespaces
```

### Check Security Status

```bash
# Fail2ban
fail2ban-client status

# Firewall
ufw status

# AppArmor
aa-status

# Audit rules
auditctl -l

# Security scan
/usr/local/bin/glucosync-security-scan.sh
```

### Run Security Audit

```bash
lynis audit system --quick
```

### View Security Logs

```bash
# Failed login attempts
grep "Failed password" /var/log/auth.log

# Fail2ban logs
tail -f /var/log/fail2ban.log

# Security scan logs
tail -f /var/log/glucosync-security.log

# Audit logs
tail -f /var/log/audit/audit.log
```

## Maintenance

### Update Security Packages

```bash
apt-get update
apt-get upgrade -y
```

### Review Fail2Ban Statistics

```bash
fail2ban-client status sshd
```

### Unban an IP Address

```bash
fail2ban-client set sshd unbanip <ip-address>
```

### Add Custom Firewall Rule

```bash
ufw allow from <trusted-ip> to any port <port> comment 'Description'
ufw reload
```

### Update Audit Rules

1. Edit `/etc/audit/rules.d/glucosync.rules`
2. Reload: `systemctl restart auditd`

## Security Best Practices

1. **SSH Keys Only**: Never use password authentication
2. **Regular Updates**: Keep all packages up to date
3. **Monitor Logs**: Review security logs regularly
4. **Backup Secrets**: Store K3s tokens and secrets securely
5. **Firewall Rules**: Only open required ports
6. **Regular Audits**: Run Lynis audits monthly
7. **File Integrity**: Check AIDE reports for unauthorized changes
8. **Network Segmentation**: Use Kubernetes Network Policies
9. **RBAC**: Implement proper Role-Based Access Control
10. **TLS Everywhere**: Use cert-manager for all services

## Troubleshooting

### Issue: Path not found error

**Symptom**: `error: the path "../k8s/base/namespaces/namespaces.yaml" does not exist`

**Solution**: The updated script now uses absolute paths. Make sure you're running the script from the correct location:
```bash
cd /path/to/glucosync-k8s/scripts
sudo ./cluster-setup.sh
```

### Issue: Firewall blocking connections

**Check Rules**:
```bash
ufw status numbered
```

**Disable temporarily** (for debugging only):
```bash
ufw disable
```

**Re-enable**:
```bash
ufw enable
```

### Issue: Fail2ban banning legitimate IPs

**Check banned IPs**:
```bash
fail2ban-client status sshd
```

**Unban IP**:
```bash
fail2ban-client set sshd unbanip <ip-address>
```

**Whitelist IP**:
Edit `/etc/fail2ban/jail.local` and add under `[DEFAULT]`:
```
ignoreip = 127.0.0.1/8 ::1 <your-trusted-ip>
```

### Issue: K3s not starting

**Check logs**:
```bash
journalctl -u k3s -f
```

**Check firewall**:
```bash
ufw allow 6443/tcp
```

## Security Monitoring Checklist

- [ ] Review fail2ban status daily
- [ ] Check security scan logs daily
- [ ] Review audit logs weekly
- [ ] Run Lynis audit monthly
- [ ] Check AIDE integrity weekly
- [ ] Review firewall rules monthly
- [ ] Update all packages monthly
- [ ] Rotate logs regularly
- [ ] Backup security configuration
- [ ] Test incident response procedures

## Additional Resources

- [K3s Security Best Practices](https://docs.k3s.io/security/hardening-guide)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [Lynis Documentation](https://cisofy.com/lynis/)
- [Fail2Ban Documentation](https://www.fail2ban.org/)
- [UFW Documentation](https://help.ubuntu.com/community/UFW)

## Support

For issues or questions:
1. Check logs in `/var/log/glucosync-security.log`
2. Run security scan: `/usr/local/bin/glucosync-security-scan.sh`
3. Review this documentation
4. Check Kubernetes logs: `kubectl logs -n <namespace> <pod>`

---

**Last Updated**: February 2026
**Script Version**: 2.0 (Security Hardened)
