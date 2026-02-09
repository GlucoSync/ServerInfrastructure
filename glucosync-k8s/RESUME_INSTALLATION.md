# GlucoSync Cluster Setup - Quick Resume Guide

## Your Current Status

Based on the installation logs, here's what you have:

### ✅ Successfully Installed
1. System security hardening (fail2ban, UFW, SSH hardening, etc.)
2. K3s control plane
3. Namespaces (all 6 created)
4. Longhorn storage (core installation complete)
5. Postgres Operator (just installed)

### ❌ Still Need to Install
1. cert-manager
2. Nginx Ingress Controller (attempted but failed due to kubeconfig issue - NOW FIXED)
3. Secrets (interactive setup)

## Issues Fixed

### Issue 1: Helm Can't Reach Kubernetes
**Error**: `Kubernetes cluster unreachable: Get "http://localhost:8080/version"`

**Fix Applied**: Added `export KUBECONFIG=/etc/rancher/k3s/k3s.yaml` to the script

### Issue 2: Postgres Operator Wait Failed
**Error**: `error: no matching resources found`

**Fix Applied**: Updated wait command to try multiple label selectors and fall back to manual verification

## How to Resume Installation

### Option 1: Install Remaining Components Individually (Recommended)

```bash
cd /home/admin/ServerInfrastructure/glucosync-k8s/scripts
sudo ./cluster-setup.sh

# Then select in order:
# 4 - Install cert-manager
# 5 - Install Nginx Ingress Controller (now fixed!)
# 8 - Create Secrets
```

### Option 2: Quick One-Liner

```bash
cd /home/admin/ServerInfrastructure/glucosync-k8s/scripts

# Install cert-manager
sudo kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# Wait for cert-manager
sudo kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s

# Install Helm (if not already installed)
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sudo bash

# Install Nginx Ingress
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
sudo -E helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
sudo -E helm repo update
sudo -E helm install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    --create-namespace

# Add firewall rules for HTTP/HTTPS
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw reload
```

## Verify Installation

### Check K3s
```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes
```

### Check All Pods
```bash
kubectl get pods -A
```

### Check Namespaces
```bash
kubectl get namespaces | grep glucosync
```

Expected output:
```
glucosync-admin         Active   Xm
glucosync-cicd          Active   Xm
glucosync-core          Active   Xm
glucosync-data          Active   Xm
glucosync-monitoring    Active   Xm
glucosync-services      Active   Xm
```

### Check Longhorn
```bash
kubectl get pods -n longhorn-system
kubectl get storageclass
```

### Check Postgres Operator
```bash
kubectl get pods -n default | grep postgres-operator
```

### Check cert-manager (after installation)
```bash
kubectl get pods -n cert-manager
```

### Check Nginx Ingress (after installation)
```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

## Next Steps After Installation

1. **Create Secrets** (option 8 in menu)
   - Cloudflare API token
   - MongoDB credentials
   - Redis credentials
   - MinIO credentials

2. **Deploy Databases**
   ```bash
   cd /home/admin/ServerInfrastructure/glucosync-k8s/scripts
   sudo ./deploy-databases.sh
   ```

3. **Configure DNS**
   - Point your domain to the cluster IP: `161.97.160.177`
   - Create A records for:
     - api.glucosync.io
     - longhorn.glucosync.io
     - monitoring.glucosync.io
     - etc.

4. **Configure Cert-Manager Issuer**
   ```bash
   kubectl apply -f k8s/base/networking/cert-manager/cluster-issuer.yaml
   ```

5. **Deploy Applications**
   - Apply your application manifests
   - Configure ingress rules
   - Set up monitoring

## Troubleshooting

### If kubectl doesn't work
```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
# Or as root:
sudo su
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

### If Helm doesn't work
```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
sudo -E helm list -A
```

### Check K3s Service
```bash
systemctl status k3s
journalctl -u k3s -f
```

### Check Security Status
```bash
# Firewall
ufw status numbered

# Fail2ban
fail2ban-client status

# Security scan
/usr/local/bin/glucosync-security-scan.sh
```

## Important Notes

1. **K3s Token** (save this!):
   ```
   K10f1638382fa34b77e487a4aef1b523ae190957042950f159c082449a6afe883f2::server:6ddfe445c5ee30972c101a8750cb7e20
   ```

2. **K3s URL** (for worker nodes):
   ```
   https://161.97.160.177:6443
   ```

3. **Always use root or sudo** when running cluster operations

4. **Set KUBECONFIG** before running kubectl/helm commands:
   ```bash
   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
   ```

## Re-run Fixed Script

The script has been updated with fixes. To get the latest version:

```bash
cd /home/admin/ServerInfrastructure/glucosync-k8s
git pull  # If using git
# Or re-upload the fixed script
```

Then run:
```bash
cd /home/admin/ServerInfrastructure/glucosync-k8s/scripts
sudo ./cluster-setup.sh
```

---

**Script Version**: 2.1 (Fixed kubeconfig and postgres operator)
**Last Updated**: February 2026
