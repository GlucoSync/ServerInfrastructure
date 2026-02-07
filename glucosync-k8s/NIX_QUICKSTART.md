# NixOS Quick Start - GlucoSync Kubernetes

**Complete deployment in 15 minutes!**

## Prerequisites

- [ ] 3-4 servers with fresh NixOS installed (or any Linux with Nix)
- [ ] SSH access as root to all servers
- [ ] Static IPs assigned to all servers
- [ ] Your SSH private key at `~/.ssh/id_ed25519`

## Step 1: Prepare Your Machine

```bash
# Install Nix (if not on NixOS)
curl -L https://nixos.org/nix/install | sh

# Enable flakes
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf

# Source Nix
. ~/.nix-profile/etc/profile.d/nix.sh
```

## Step 2: Clone Repository

```bash
git clone <your-repo-url> glucosync-k8s
cd glucosync-k8s
```

## Step 3: Generate Hardware Configs

For each server, run:

```bash
# Control Plane
ssh root@<CONTROL_PLANE_IP> "nixos-generate-config --show-hardware-config" \
  > nixos/hardware-configuration-control-plane.nix

# Worker 1
ssh root@<WORKER1_IP> "nixos-generate-config --show-hardware-config" \
  > nixos/hardware-configuration-worker1.nix

# Worker 2
ssh root@<WORKER2_IP> "nixos-generate-config --show-hardware-config" \
  > nixos/hardware-configuration-worker2.nix

# Worker 3 (optional)
ssh root@<WORKER3_IP> "nixos-generate-config --show-hardware-config" \
  > nixos/hardware-configuration-worker3.nix

# HAProxy
ssh root@<HAPROXY_IP> "nixos-generate-config --show-hardware-config" \
  > nixos/hardware-configuration-haproxy.nix
```

## Step 4: Update Imports

Edit each node config to use the correct hardware configuration:

```bash
# Control plane
sed -i 's|./hardware-configuration.nix|./hardware-configuration-control-plane.nix|' nixos/control-plane.nix

# Worker
sed -i 's|./hardware-configuration.nix|./hardware-configuration-worker1.nix|' nixos/worker.nix

# HAProxy
sed -i 's|./hardware-configuration.nix|./hardware-configuration-haproxy.nix|' nixos/haproxy.nix
```

## Step 5: Deploy!

```bash
# Export your server IPs
export CONTROL_PLANE_IP="192.168.1.10"
export WORKER1_IP="192.168.1.11"
export WORKER2_IP="192.168.1.12"
export WORKER3_IP="192.168.1.13"  # Optional
export HAPROXY_IP="192.168.1.20"

# Run deployment (takes ~10 minutes)
./scripts/deploy-cluster-nix.sh
```

The script will:
- ✅ Deploy NixOS with security hardening to all nodes
- ✅ Install and configure K3s
- ✅ Join workers to control plane
- ✅ Deploy HAProxy load balancer
- ✅ Install Kubernetes components (cert-manager, Ingress, Longhorn, etc.)

## Step 6: Verify

```bash
# SSH to control plane
ssh afonso@$CONTROL_PLANE_IP

# Check nodes
kubectl get nodes

# Check pods
kubectl get pods -A
```

Expected output:
```
NAME                     STATUS   ROLES                  AGE
glucosync-control-plane  Ready    control-plane,master   5m
glucosync-worker1        Ready    <none>                 3m
glucosync-worker2        Ready    <none>                 3m
```

## Step 7: Access Services

```bash
# Get ArgoCD admin password
ssh root@$CONTROL_PLANE_IP \
  "kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"

# Access dashboards (after DNS is configured)
# Grafana: https://grafana.glucosync.io
# ArgoCD: https://argocd.glucosync.io
# Prometheus: https://prometheus.glucosync.io
```

## Step 8: Deploy Applications

```bash
# Deploy databases
kubectl apply -f k8s/base/databases/

# Deploy applications
kubectl apply -f k8s/base/applications/

# Deploy monitoring
kubectl apply -f k8s/base/monitoring/
```

## 🎉 Done!

Your cluster is now:
- ✅ Fully deployed and operational
- ✅ Hardened with fail2ban, AppArmor, firewall
- ✅ Configured with your SSH key only
- ✅ Running K3s with high availability
- ✅ Ready for application deployments

## 🔒 Security Features Active

All nodes automatically have:
- Fail2ban (SSH brute force protection)
- Firewall enabled (minimal ports open)
- SSH key-only authentication
- AppArmor mandatory access control
- Audit logging for all critical events
- Automated security scans
- File integrity monitoring (AIDE)

## 🛠️ Quick Commands

```bash
# Check security status
ssh afonso@$CONTROL_PLANE_IP
sudo fail2ban-client status sshd

# Check cluster health
kubectl get nodes
kubectl get pods -A

# Check HAProxy stats
curl http://$HAPROXY_IP:8404/stats

# View K3s logs
sudo journalctl -u k3s -f
```

## 🔄 Making Changes

```bash
# Edit any Nix config
vim nixos/common.nix

# Redeploy to apply changes
nixos-rebuild switch \
  --flake .#glucosync-control-plane \
  --target-host root@$CONTROL_PLANE_IP
```

## 📚 Next Steps

1. Configure DNS to point to `$HAPROXY_IP`
2. Deploy your applications
3. Set up CI/CD with Gitea + Woodpecker
4. Configure backups with Velero
5. Import Grafana dashboards

See [NIX_DEPLOYMENT_GUIDE.md](NIX_DEPLOYMENT_GUIDE.md) for detailed documentation.

---

**Time to deployment: ~15 minutes** ⚡
