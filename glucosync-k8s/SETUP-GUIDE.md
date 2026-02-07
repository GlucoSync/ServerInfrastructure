# GlucoSync Kubernetes Setup Guide - Fresh Ubuntu Install

Complete guide to deploy GlucoSync Kubernetes infrastructure from a fresh Ubuntu installation.

## Prerequisites

### Hardware Requirements

**Single-Node Cluster (Development/Small Scale):**
- 1 server with Ubuntu 22.04 LTS
- 16GB RAM
- 8+ CPU cores
- 500GB SSD
- Static IP address

**Multi-Node Cluster (Production):**
- Control Plane: 16GB RAM, 8+ cores, 500GB SSD
- Workers (1-3): 8GB RAM, 4+ cores, 200GB SSD each
- All nodes need static IP addresses

### Network Requirements
- SSH access to all servers
- Servers can reach the internet
- Domain name (e.g., glucosync.io)
- Cloudflare account for DNS and SSL

---

## Part 1: Prepare Your Management Machine (Ubuntu)

This is the machine you'll deploy FROM (can be your laptop or a separate server).

### Step 1: Install Nix Package Manager

```bash
# Install Nix (multi-user installation)
sudo apt update
sudo apt install -y curl git
sh <(curl -L https://nixos.org/nix/install) --daemon

# Reload shell
source /etc/profile.d/nix.sh

# Verify installation
nix --version
```

### Step 2: Enable Nix Flakes

```bash
# Create nix config directory
mkdir -p ~/.config/nix

# Enable flakes and nix-command
cat > ~/.config/nix/nix.conf <<EOF
experimental-features = nix-command flakes
EOF
```

### Step 3: Clone the Repository

```bash
# Create working directory
mkdir -p ~/ServerInfrastructure
cd ~/ServerInfrastructure

# Clone your repository (adjust URL as needed)
git clone <YOUR_REPO_URL> glucosync-k8s
cd glucosync-k8s
```

### Step 4: Test Nix Development Shell

```bash
# Enter the development shell (this will download all tools)
nix develop

# You should see a welcome message with available tools
# Type 'exit' to leave the shell for now
```

---

## Part 2: Prepare Target Servers (NixOS Installation)

You have two options: run on Ubuntu with Nix, or install NixOS for better integration.

### Option A: Use Ubuntu with Nix (Quicker)

On each target server (control plane and workers):

```bash
# SSH into the server
ssh root@YOUR_SERVER_IP

# Install Nix
curl -L https://nixos.org/nix/install | sh -s -- --daemon
source /etc/profile.d/nix.sh

# Enable flakes
mkdir -p /root/.config/nix
cat > /root/.config/nix/nix.conf <<EOF
experimental-features = nix-command flakes
EOF

# Install required tools
nix-env -iA nixpkgs.k3s nixpkgs.kubectl
```

**Note:** This is simpler but the NixOS configurations won't fully apply. For production, Option B is recommended.

### Option B: Install NixOS (Recommended for Production)

This gives you full declarative configuration.

1. Boot each server from NixOS ISO (download from https://nixos.org/download.html)
2. Follow the installation guide: https://nixos.org/manual/nixos/stable/#sec-installation
3. Basic installation commands:

```bash
# After booting into NixOS installer
# Partition disk (example for /dev/sda)
parted /dev/sda -- mklabel gpt
parted /dev/sda -- mkpart primary 512MiB 100%
parted /dev/sda -- mkpart ESP fat32 1MiB 512MiB
parted /dev/sda -- set 2 esp on

# Format partitions
mkfs.ext4 -L nixos /dev/sda1
mkfs.fat -F 32 -n boot /dev/sda2

# Mount filesystems
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-label/boot /mnt/boot

# Generate config
nixos-generate-config --root /mnt

# Edit configuration to enable SSH and set root password
nano /mnt/etc/nixos/configuration.nix

# Add these lines:
# services.openssh.enable = true;
# services.openssh.settings.PermitRootLogin = "yes";
# users.users.root.initialPassword = "changeme";

# Install
nixos-install

# Reboot
reboot
```

After installation, SSH into the server and:

```bash
# Change root password
passwd

# Add your SSH key
mkdir -p /root/.ssh
nano /root/.ssh/authorized_keys
# Paste your public SSH key

chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys
```

---

## Part 3: Set Up SSH Keys

On your management machine:

```bash
# Generate SSH key if you don't have one
ssh-keygen -t ed25519 -C "glucosync-deploy"

# Copy your public key to each server
ssh-copy-id root@YOUR_CONTROL_PLANE_IP
ssh-copy-id root@YOUR_WORKER1_IP  # if using workers
ssh-copy-id root@YOUR_WORKER2_IP  # if using workers

# Test SSH access
ssh root@YOUR_CONTROL_PLANE_IP
```

---

## Part 4: Update NixOS Configuration with Your SSH Key

Edit the common.nix file to add your SSH public key:

```bash
cd ~/ServerInfrastructure/glucosync-k8s

# Get your public key
cat ~/.ssh/id_ed25519.pub

# Edit the config
nano nixos/common.nix
```

Find these sections and update with YOUR public key:

```nix
users.users.afonso = {
  isNormalUser = true;
  extraGroups = [ "wheel" "docker" "systemd-journal" ];

  openssh.authorizedKeys.keys = [
    "ssh-ed25519 YOUR_PUBLIC_KEY_HERE your@email.com"
  ];

  hashedPassword = null;
};

users.users.root = {
  openssh.authorizedKeys.keys = [
    "ssh-ed25519 YOUR_PUBLIC_KEY_HERE your@email.com"
  ];
};
```

You can also change the username from "afonso" to your preferred username.

---

## Part 5: Deploy the Cluster

### Single-Node Deployment (Simplest)

From your management machine:

```bash
cd ~/ServerInfrastructure/glucosync-k8s

# Run the deployment script
./scripts/deploy-cluster-nix.sh

# When prompted:
# - Enter your control plane IP (e.g., 161.97.160.177)
# - Choose "no" for workers
# - Confirm deployment with "yes"
```

The script will:
1. Deploy NixOS configuration to the control plane
2. Install K3s Kubernetes
3. Install HAProxy load balancer
4. Wait for K3s to initialize
5. Install all Kubernetes components (cert-manager, ingress, storage, etc.)

**Deployment time:** ~10-15 minutes

### Multi-Node Deployment (Production)

```bash
cd ~/ServerInfrastructure/glucosync-k8s

# Run the deployment script
./scripts/deploy-cluster-nix.sh

# When prompted:
# - Enter your control plane IP
# - Choose "yes" for workers
# - Enter worker IPs (you can leave some empty)
# - Confirm deployment with "yes"
```

The script will:
1. Deploy control plane
2. Deploy each worker node
3. Join workers to the cluster
4. Configure HAProxy with worker backends
5. Install all components

**Deployment time:** ~15-25 minutes depending on worker count

---

## Part 6: Verify the Deployment

### Check Cluster Status

```bash
# SSH into control plane
ssh root@YOUR_CONTROL_PLANE_IP

# Set kubeconfig
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Check nodes
kubectl get nodes

# Should show:
# NAME                   STATUS   ROLE                  AGE     VERSION
# glucosync-control-plane   Ready    control-plane,master   5m   v1.28.x
# glucosync-worker          Ready    <none>                 3m   v1.28.x  (if workers deployed)

# Check all pods
kubectl get pods -A

# Check HAProxy status
systemctl status haproxy

# View HAProxy stats
curl http://localhost:8404/stats
```

### Access Services

From your local machine:

```bash
# Port forward Grafana
ssh -L 3000:localhost:3000 root@YOUR_CONTROL_PLANE_IP
# Open http://localhost:3000 in browser

# Port forward ArgoCD
ssh -L 8080:localhost:8080 root@YOUR_CONTROL_PLANE_IP
# Open http://localhost:8080 in browser
```

---

## Part 7: Configure DNS

### In Cloudflare (or your DNS provider)

Add these DNS records pointing to your **control plane IP**:

```
Type    Name                        Value
A       glucosync.io                YOUR_CONTROL_PLANE_IP
A       *.glucosync.io              YOUR_CONTROL_PLANE_IP
```

Or individual records:
```
A       api.glucosync.io            YOUR_CONTROL_PLANE_IP
A       app.glucosync.io            YOUR_CONTROL_PLANE_IP
A       grafana.glucosync.io        YOUR_CONTROL_PLANE_IP
A       argocd.glucosync.io         YOUR_CONTROL_PLANE_IP
A       auth.glucosync.io           YOUR_CONTROL_PLANE_IP
```

### Set up Cloudflare API Token for cert-manager

1. Go to Cloudflare Dashboard → My Profile → API Tokens
2. Create Token → Edit zone DNS
3. Permissions: Zone.DNS.Edit
4. Zone Resources: Include → Specific zone → glucosync.io
5. Create token and save it

```bash
# SSH into control plane
ssh root@YOUR_CONTROL_PLANE_IP

# Create secret for cert-manager
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token=YOUR_CLOUDFLARE_TOKEN \
  -n cert-manager
```

---

## Part 8: Deploy Databases

```bash
# SSH into control plane
ssh root@YOUR_CONTROL_PLANE_IP

# Deploy databases (this is interactive)
cd /etc/glucosync-k8s
./scripts/deploy-databases.sh

# Follow prompts to set passwords for:
# - MongoDB
# - Redis  
# - PostgreSQL
# - MinIO
```

---

## Part 9: Deploy Applications

### Option A: Manual Deployment

```bash
# SSH into control plane
ssh root@YOUR_CONTROL_PLANE_IP
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Deploy applications
kubectl apply -f /etc/glucosync-k8s/k8s/base/applications/glucoengine/
kubectl apply -f /etc/glucosync-k8s/k8s/base/applications/mainwebsite/
kubectl apply -f /etc/glucosync-k8s/k8s/base/applications/newclient/

# Check deployment status
kubectl get pods -n glucosync-core
```

### Option B: GitOps with ArgoCD

```bash
# Get ArgoCD admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d

# Access ArgoCD UI
# Port forward: ssh -L 8080:localhost:8080 root@YOUR_CONTROL_PLANE_IP
# Open http://localhost:8080
# Login with username: admin, password: (from above)

# Create applications in ArgoCD UI or via CLI
```

---

## Part 10: Post-Deployment Checklist

- [ ] All nodes show as Ready: `kubectl get nodes`
- [ ] All pods are running: `kubectl get pods -A`
- [ ] HAProxy is running: `systemctl status haproxy`
- [ ] DNS records are pointing to control plane IP
- [ ] SSL certificates are issued: `kubectl get certificate -A`
- [ ] Grafana is accessible: https://grafana.glucosync.io
- [ ] ArgoCD is accessible: https://argocd.glucosync.io
- [ ] Can access applications: https://app.glucosync.io
- [ ] Backups are configured
- [ ] Monitoring alerts are set up

---

## Troubleshooting

### Can't SSH into server
```bash
# Check if SSH is running
systemctl status sshd

# Check firewall
sudo ufw status
sudo ufw allow 22/tcp
```

### Nix command not found
```bash
# Source nix profile
source /etc/profile.d/nix.sh

# Or add to ~/.bashrc
echo 'source /etc/profile.d/nix.sh' >> ~/.bashrc
```

### nixos-rebuild fails
```bash
# Check SSH connection
ssh root@YOUR_SERVER_IP

# Check if server is NixOS
cat /etc/os-release

# Verify flake.nix exists
ls -la ~/ServerInfrastructure/glucosync-k8s/flake.nix
```

### K3s won't start
```bash
# SSH into control plane
ssh root@YOUR_CONTROL_PLANE_IP

# Check logs
journalctl -u k3s -f

# Check if ports are available
ss -tulpn | grep -E ':(6443|10250|2379|2380)'

# Restart K3s
systemctl restart k3s
```

### Pods stuck in Pending
```bash
# Check node resources
kubectl describe nodes

# Check pod events
kubectl describe pod POD_NAME -n NAMESPACE

# Check if storage class exists
kubectl get storageclass
```

### DNS not resolving
```bash
# Verify DNS records
dig glucosync.io
dig api.glucosync.io

# Check if HAProxy is routing correctly
curl -v http://YOUR_CONTROL_PLANE_IP
curl -v -H "Host: api.glucosync.io" http://YOUR_CONTROL_PLANE_IP
```

### Certificates not issued
```bash
# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager -f

# Check certificate status
kubectl describe certificate -A

# Verify Cloudflare token
kubectl get secret cloudflare-api-token -n cert-manager -o yaml
```

---

## Maintenance Commands

### Update the cluster
```bash
# From management machine
cd ~/ServerInfrastructure/glucosync-k8s

# Pull latest changes
git pull

# Re-deploy
./scripts/deploy-cluster-nix.sh
```

### Scale applications
```bash
# SSH into control plane
ssh root@YOUR_CONTROL_PLANE_IP
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Scale deployment
kubectl scale deployment glucoengine -n glucosync-core --replicas=5
```

### View logs
```bash
# Application logs
kubectl logs -n glucosync-core -l app=glucoengine --tail=100 -f

# Ingress logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -f

# HAProxy logs
ssh root@YOUR_CONTROL_PLANE_IP
journalctl -u haproxy -f
```

### Backup etcd
```bash
# Automatic backups run daily, stored in /var/backups/k3s-etcd/

# Manual backup
ssh root@YOUR_CONTROL_PLANE_IP
systemctl start k3s-etcd-backup.service

# List backups
ls -lh /var/backups/k3s-etcd/
```

---

## Adding Workers Later

If you start with single-node and want to add workers:

```bash
# From management machine
cd ~/ServerInfrastructure/glucosync-k8s

# Get join token from control plane
ssh root@YOUR_CONTROL_PLANE_IP "cat /root/k3s-join-info.txt"

# Deploy worker
export WORKER_IP="192.168.1.11"
export K3S_URL="https://YOUR_CONTROL_PLANE_IP:6443"
export K3S_TOKEN="TOKEN_FROM_ABOVE"

# Create k3s config on worker
ssh root@$WORKER_IP "mkdir -p /etc/rancher/k3s"
ssh root@$WORKER_IP "cat > /etc/rancher/k3s/k3s.env <<EOF
K3S_URL=$K3S_URL
K3S_TOKEN=$K3S_TOKEN
EOF"

# Deploy worker config
nixos-rebuild switch \
    --flake .#glucosync-worker \
    --target-host "root@$WORKER_IP" \
    --build-host localhost

# Update HAProxy config on control plane
ssh root@YOUR_CONTROL_PLANE_IP
nano /etc/haproxy/haproxy.cfg
# Add: server worker1 WORKER_IP:30443 check
systemctl reload haproxy
```

---

## Security Hardening

### Change default passwords
```bash
# SSH into control plane
ssh root@YOUR_CONTROL_PLANE_IP

# Change ArgoCD password
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
argocd login localhost:8080
argocd account update-password

# Rotate Cloudflare token periodically
# Update database passwords in sealed secrets
```

### Set up firewall rules
```bash
# Control plane
ufw allow 22/tcp     # SSH
ufw allow 80/tcp     # HTTP
ufw allow 443/tcp    # HTTPS
ufw allow 6443/tcp   # K8s API
ufw enable

# Workers (only need SSH from control plane)
ufw allow from YOUR_CONTROL_PLANE_IP to any port 22
ufw enable
```

### Enable monitoring alerts
```bash
# Configure Prometheus alerting rules
# Configure Alertmanager for email/Slack notifications
# See monitoring/alerts/ directory
```

---

## Cost Optimization

### Single-Node Providers & Costs

**Hetzner (Recommended):**
- AX41: €39/month (AMD Ryzen 5 3600, 64GB RAM, 512GB NVMe)

**OVH:**
- Rise-1: $50/month (Intel Xeon, 32GB RAM, 500GB SSD)

**Contabo:**
- VPS L: €12/month (8 cores, 30GB RAM, 800GB SSD)

### Multi-Node Setup
- Control Plane: $40-80/month
- Workers: $20-40/month each
- **Total 3-node cluster:** $80-160/month

---

## Next Steps

After successful deployment:

1. **Set up monitoring alerts** - Configure Alertmanager
2. **Configure backups** - Set up Velero for full cluster backups
3. **Deploy applications** - Roll out your services
4. **Load testing** - Test your infrastructure under load
5. **Documentation** - Document your specific setup
6. **Team access** - Set up RBAC for team members
7. **CI/CD** - Configure Woodpecker/GitOps workflows

---

## Getting Help

- **Documentation:** See README.md and DEPLOYMENT.md
- **Issues:** Check logs with `kubectl logs` and `journalctl`
- **Community:** NixOS forum, Kubernetes Slack
- **Emergency:** See docs/runbooks/disaster-recovery.md

---

## Summary

You now have:
- ✅ Fully declarative infrastructure with NixOS
- ✅ Kubernetes cluster with K3s
- ✅ HAProxy load balancer on control plane
- ✅ Automatic SSL certificates with cert-manager
- ✅ Monitoring with Prometheus & Grafana
- ✅ GitOps with ArgoCD
- ✅ Persistent storage with Longhorn
- ✅ Scalable from 1 to multiple nodes

Your cluster is production-ready! 🎉
