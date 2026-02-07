# GlucoSync Kubernetes - NixOS Deployment Guide

This guide covers deploying the GlucoSync Kubernetes infrastructure using **NixOS and Flakes** for a fully declarative, reproducible, and OS-agnostic setup.

## 🎯 Why Nix/NixOS?

- ✅ **Declarative Configuration** - Everything is code, version controlled
- ✅ **Reproducible Builds** - Same config = same result, every time
- ✅ **OS-Agnostic** - Works on any Linux distribution with Nix
- ✅ **Atomic Upgrades** - Rollback to previous configuration if something breaks
- ✅ **No Dependency Hell** - Nix handles all dependencies
- ✅ **Built-in Security** - Hardened SSH, fail2ban, AppArmor, audit logging
- ✅ **Immutable Infrastructure** - Changes via configuration, not manual edits

## 📋 Prerequisites

### 1. Install NixOS on All Servers

**Option A: Fresh NixOS Installation**
```bash
# Download NixOS ISO
wget https://channels.nixos.org/nixos-23.11/latest-nixos-minimal-x86_64-linux.iso

# Boot from ISO and run installer
nixos-install
```

**Option B: Install Nix on Existing Linux**
```bash
# Install Nix package manager on any Linux distro
curl -L https://nixos.org/nix/install | sh

# Enable flakes
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

### 2. Server Requirements

- **Control Plane**: 1 server
  - CPU: 8 cores
  - RAM: 16GB
  - Storage: 500GB SSD

- **Workers**: 2-3 servers
  - CPU: 8 cores each
  - RAM: 16GB each
  - Storage: 500GB SSD each

- **HAProxy**: 1 server (can be smaller)
  - CPU: 2-4 cores
  - RAM: 4-8GB
  - Storage: 50GB

### 3. Network Requirements

- All servers must have static IPs
- Servers must be able to communicate with each other
- SSH access to all servers as root (initially)

## 🚀 Quick Start (Automated Deployment)

### Step 1: Clone Repository

```bash
git clone <your-repo-url> glucosync-k8s
cd glucosync-k8s
```

### Step 2: Generate Hardware Configurations

On each server, generate hardware configuration:

```bash
# SSH to each server
ssh root@<SERVER_IP>

# Generate hardware config
nixos-generate-config --show-hardware-config > /tmp/hardware-configuration.nix

# Copy back to your local machine
exit
scp root@<SERVER_IP>:/tmp/hardware-configuration.nix ./nixos/hardware-configuration-<node>.nix
```

Repeat for all nodes, naming them:
- `hardware-configuration-control-plane.nix`
- `hardware-configuration-worker1.nix`
- `hardware-configuration-worker2.nix`
- `hardware-configuration-worker3.nix`
- `hardware-configuration-haproxy.nix`

### Step 3: Update Hardware Configs in Nix Files

Update the import in each node config:

```nix
# nixos/control-plane.nix
imports = [
  ./hardware-configuration-control-plane.nix  # Update this line
];

# nixos/worker.nix
imports = [
  ./hardware-configuration-worker1.nix  # Update this line
];

# nixos/haproxy.nix
imports = [
  ./hardware-configuration-haproxy.nix  # Update this line
];
```

### Step 4: Set Up SSH Keys

Your SSH key is already configured in the flake:
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKsuV7znGPzAetFbhPMYXkxErmn1NJpdTVoFIO5ngZH/ afonso@arka
```

Ensure you have the corresponding private key at `~/.ssh/id_ed25519`.

### Step 5: Deploy Cluster

```bash
# Set environment variables (or enter interactively)
export CONTROL_PLANE_IP="192.168.1.10"
export WORKER1_IP="192.168.1.11"
export WORKER2_IP="192.168.1.12"
export WORKER3_IP="192.168.1.13"
export HAPROXY_IP="192.168.1.20"

# Run deployment script
./scripts/deploy-cluster-nix.sh
```

The script will:
1. Deploy control plane
2. Deploy all worker nodes
3. Deploy HAProxy load balancer
4. Install Kubernetes components
5. Verify cluster health

**Estimated time**: 10-15 minutes

## 📝 Manual Deployment (Step by Step)

### 1. Deploy Control Plane

```bash
nixos-rebuild switch \
  --flake .#glucosync-control-plane \
  --target-host root@<CONTROL_PLANE_IP> \
  --build-host localhost
```

Wait for deployment to complete and K3s to initialize (30 seconds).

### 2. Get K3s Token

```bash
ssh root@<CONTROL_PLANE_IP> "cat /root/k3s-join-info.txt"
```

Note the `K3S_URL` and `K3S_TOKEN`.

### 3. Deploy Workers

For each worker:

```bash
# Create environment file with K3s connection info
ssh root@<WORKER_IP> "mkdir -p /etc/rancher/k3s"
ssh root@<WORKER_IP> "cat > /etc/rancher/k3s/k3s.env <<EOF
K3S_URL=https://<CONTROL_PLANE_IP>:6443
K3S_TOKEN=<K3S_TOKEN>
EOF"

# Deploy worker
nixos-rebuild switch \
  --flake .#glucosync-worker \
  --target-host root@<WORKER_IP> \
  --build-host localhost
```

### 4. Verify Cluster

```bash
ssh root@<CONTROL_PLANE_IP>
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes
```

All nodes should show as `Ready`.

### 5. Deploy HAProxy

```bash
# Update nixos/haproxy.nix with actual worker IPs
# Then deploy:
nixos-rebuild switch \
  --flake .#glucosync-haproxy \
  --target-host root@<HAPROXY_IP> \
  --build-host localhost
```

### 6. Install Kubernetes Components

```bash
ssh root@<CONTROL_PLANE_IP>
/etc/glucosync-scripts/install-components.sh
```

This installs:
- cert-manager
- Nginx Ingress Controller
- Longhorn storage
- Postgres Operator
- Prometheus Operator
- ArgoCD
- Sealed Secrets

## 🔒 Security Features (Built-in)

All nodes come with comprehensive security hardening:

### SSH Hardening
- ✅ Only SSH key authentication (your ed25519 key)
- ✅ No password authentication
- ✅ No root password login
- ✅ Rate limiting (max 4 connections per minute)
- ✅ X11 forwarding disabled

### Fail2ban Protection
- ✅ SSH brute force protection (3 attempts = 1 hour ban)
- ✅ Ban time increases exponentially
- ✅ Kubernetes API protection
- ✅ Cross-jail banning

### System Hardening
- ✅ AppArmor enabled
- ✅ Audit logging for all critical events
- ✅ Firewall enabled with minimal open ports
- ✅ Kernel hardening (sysctl parameters)
- ✅ No unnecessary services

### Security Monitoring
- ✅ Daily security scans
- ✅ Weekly Lynis audits
- ✅ File integrity monitoring (AIDE)
- ✅ Rootkit detection (rkhunter, chkrootkit)

### Check Security Status

```bash
# SSH to any node as afonso
ssh afonso@<NODE_IP>

# Check fail2ban status
sudo fail2ban-client status

# Check SSH jail
sudo fail2ban-client status sshd

# Check AppArmor
sudo aa-status

# Check audit rules
sudo auditctl -l

# Run security audit
sudo lynis audit system --quick
```

## 🔄 Updating Configuration

### Making Changes

1. Edit Nix configuration files:
```bash
vim nixos/common.nix
# or
vim nixos/modules/security.nix
```

2. Apply changes:
```bash
nixos-rebuild switch \
  --flake .#glucosync-control-plane \
  --target-host root@<CONTROL_PLANE_IP>
```

3. Changes are applied atomically - if anything fails, the system rolls back!

### Rolling Back

If something goes wrong:

```bash
# SSH to the node
ssh root@<NODE_IP>

# List previous generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# Rollback to previous generation
sudo /nix/var/nix/profiles/system-<N>-link/bin/switch-to-configuration switch
```

## 🛠️ Development Shell

Enter a development shell with all tools:

```bash
nix develop

# You now have access to:
# - kubectl, helm, k9s, kubectx
# - argocd, velero
# - docker, docker-compose
# - mc (MinIO client)
# - and more...
```

## 📊 Monitoring

All monitoring is built-in and configured:

### Access Dashboards

```bash
# Grafana
https://grafana.glucosync.io

# Prometheus
https://prometheus.glucosync.io

# ArgoCD
https://argocd.glucosync.io

# Longhorn UI
https://longhorn.glucosync.io

# HAProxy Stats
http://<HAPROXY_IP>:8404/stats
```

### Get ArgoCD Admin Password

```bash
ssh root@<CONTROL_PLANE_IP>
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d
```

## 🗂️ File Structure

```
glucosync-k8s/
├── flake.nix                          # Main Nix flake
├── nixos/
│   ├── common.nix                     # Shared configuration
│   ├── control-plane.nix              # Control plane config
│   ├── worker.nix                     # Worker node config
│   ├── haproxy.nix                    # HAProxy config
│   ├── hardware-configuration.nix     # Template
│   └── modules/
│       ├── security.nix               # Security hardening
│       ├── k3s-server.nix             # K3s control plane
│       └── k3s-agent.nix              # K3s worker
├── scripts/
│   └── deploy-cluster-nix.sh          # Deployment script
└── k8s/                               # Kubernetes manifests (unchanged)
```

## 🔧 Troubleshooting

### Node Won't Deploy

```bash
# Check SSH connectivity
ssh root@<NODE_IP>

# Check if Nix is installed
nix --version

# Rebuild with verbose output
nixos-rebuild switch --flake .#glucosync-control-plane \
  --target-host root@<NODE_IP> --show-trace
```

### K3s Not Starting

```bash
# Check K3s status
ssh root@<CONTROL_PLANE_IP>
sudo systemctl status k3s

# View logs
sudo journalctl -u k3s -f

# Restart K3s
sudo systemctl restart k3s
```

### Worker Can't Join Cluster

```bash
# Verify token and URL
ssh root@<WORKER_IP>
cat /etc/rancher/k3s/k3s.env

# Check connectivity to control plane
curl -k https://<CONTROL_PLANE_IP>:6443

# Restart worker
sudo systemctl restart k3s
```

### Fail2ban Issues

```bash
# Check fail2ban logs
sudo journalctl -u fail2ban -f

# Unban an IP
sudo fail2ban-client set sshd unbanip <IP>

# Check current bans
sudo fail2ban-client status sshd
```

## 🚀 Next Steps After Deployment

1. **Configure DNS** - Point domains to HAProxy IP
2. **Deploy Databases** - `kubectl apply -f k8s/base/databases/`
3. **Deploy Applications** - `kubectl apply -f k8s/base/applications/`
4. **Setup CI/CD** - Deploy Gitea, Woodpecker, ArgoCD
5. **Configure Monitoring** - Import Grafana dashboards
6. **Setup Backups** - Configure Velero, database backups

## 📚 Additional Resources

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)
- [K3s Documentation](https://docs.k3s.io/)
- [Original README](README.md) - Full architecture documentation

## 🆘 Getting Help

- **Nix Issues**: #nixos on IRC (irc.libera.chat)
- **K3s Issues**: GitHub Issues
- **Security Concerns**: Check fail2ban logs and audit logs

---

**Congratulations! You now have a fully declarative, reproducible, and hardened Kubernetes cluster! 🎉**
