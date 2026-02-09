# GlucoSync VPS Reset - Pre-Flight Checklist

## Overview
This document provides a complete checklist for resetting your VPS and running a fresh cluster setup with all the fixes applied.

---

## ✅ Changes Applied (Already Done)

### 1. ClusterIssuer Fixed
**File**: `k8s/base/networking/cert-manager/cluster-issuer.yaml`
- ✅ Line 19: Added `namespace: cert-manager` to staging issuer
- ✅ Line 38: Added `namespace: cert-manager` to production issuer

### 2. Cluster Setup Script Fixed  
**File**: `scripts/cluster-setup.sh`
- ✅ Line 528: Updated comment to clarify cert-manager usage
- ✅ Line 533: Added `--namespace=cert-manager` to secret creation
- ✅ Line 536: Added confirmation message

### 3. Other Previous Fixes
- ✅ SSH service name detection (handles both `ssh` and `sshd`)
- ✅ Kubeconfig export for Helm (`KUBECONFIG=/etc/rancher/k3s/k3s.yaml`)
- ✅ Postgres Operator wait command with fallbacks
- ✅ Longhorn StorageClass conflict resolution
- ✅ Absolute path resolution for all manifests

---

## 📋 Pre-Reset Checklist

Before you reset your VPS, make sure you have:

### Information to Save
- [ ] **K3s Token** (if you want to re-use it): Currently shown as `K10f1638382fa34b77e487a4aef1b523ae190957042950f159c082449a6afe883f2::server:6ddfe445c5ee30972c101a8750cb7e20`
- [ ] **Cloudflare API Token** (you'll need to enter it during setup)
- [ ] **MongoDB root password** (for secrets setup)
- [ ] **Redis password** (for secrets setup)  
- [ ] **MinIO credentials** (username + password for secrets setup)
- [ ] **Server IP**: `161.97.160.177`

### Cloudflare DNS Records (Should Already Exist)
Verify these A records point to `161.97.160.177`:
- [ ] @ (root domain)
- [ ] www
- [ ] api
- [ ] auth
- [ ] longhorn
- [ ] grafana
- [ ] prometheus
- [ ] argocd
- [ ] git
- [ ] ci
- [ ] mlflow

### Cloudflare Settings (Should Already Be Configured)
- [ ] SSL/TLS mode: **Full (strict)**
- [ ] Always Use HTTPS: **Enabled**
- [ ] HSTS: **Enabled**
- [ ] Minimum TLS: **1.2**

---

## 🚀 VPS Reset Procedure

### Step 1: Reset Your VPS
Through your hosting provider control panel:
1. Reset/Reinstall OS to **Ubuntu 22.04 LTS** (or 20.04)
2. Make sure you have SSH access configured
3. Note the root password or ensure your SSH key is added

### Step 2: Initial Server Login
```bash
ssh root@161.97.160.177
# Or with your user
ssh your-user@161.97.160.177
```

### Step 3: Upload the Fixed Scripts
From your local machine:
```bash
# Upload the entire project
scp -r /Users/afonso/Desktop/GlucoSync/ServerOrchestrator/glucosync-k8s \
    root@161.97.160.177:/home/admin/ServerInfrastructure/

# Or if using a non-root user
scp -r /Users/afonso/Desktop/GlucoSync/ServerOrchestrator/glucosync-k8s \
    your-user@161.97.160.177:~/ServerInfrastructure/
```

Alternative method using tar:
```bash
# On local machine - create archive
cd /Users/afonso/Desktop/GlucoSync/ServerOrchestrator
tar czf glucosync-k8s.tar.gz glucosync-k8s/

# Upload
scp glucosync-k8s.tar.gz root@161.97.160.177:/tmp/

# On server - extract
ssh root@161.97.160.177
mkdir -p /home/admin/ServerInfrastructure
cd /home/admin/ServerInfrastructure
tar xzf /tmp/glucosync-k8s.tar.gz
```

### Step 4: Verify Files Are Uploaded
On the server:
```bash
cd /home/admin/ServerInfrastructure/glucosync-k8s
ls -la scripts/
cat k8s/base/networking/cert-manager/cluster-issuer.yaml | grep -A 3 "apiTokenSecretRef"
```

You should see `namespace: cert-manager` in both issuers.

### Step 5: Run the Full Setup
```bash
cd /home/admin/ServerInfrastructure/glucosync-k8s/scripts
chmod +x cluster-setup.sh
sudo ./cluster-setup.sh
```

Select option: **9 - Full Setup (Security + Control Plane)**

### Step 6: Answer the Prompts
During the setup, you'll be asked for:

1. **Cloudflare API token**: `your-cloudflare-token-here`
2. **MongoDB root password**: `your-strong-mongodb-password`
3. **Redis password**: `your-strong-redis-password`
4. **MinIO root user**: `admin` (or your choice)
5. **MinIO root password**: `your-strong-minio-password`

**Important**: Write these down! You'll need them later.

---

## ⏱️ Expected Timeline

| Step | Duration | What Happens |
|------|----------|--------------|
| System hardening | 5-10 min | Install security packages, configure firewall |
| K3s installation | 2-3 min | Install control plane |
| Namespaces | 5 sec | Create all namespaces |
| Longhorn | 3-5 min | Install storage system |
| cert-manager | 1-2 min | Install certificate manager |
| Nginx Ingress | 1-2 min | Install ingress controller |
| Postgres Operator | 1-2 min | Install database operator |
| Create secrets | 1 min | Interactive secret creation |
| **Total** | **15-25 min** | Complete cluster setup |

---

## ✅ Post-Installation Verification

After the script completes, run these verification commands:

### 1. Check Cluster Health
```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Check nodes
kubectl get nodes

# Should show:
# NAME            STATUS   ROLE                  AGE   VERSION
# vmi2757722      Ready    control-plane,master  Xm    v1.34.3+k3s1
```

### 2. Check All Pods
```bash
kubectl get pods -A

# All pods should be Running or Completed
```

### 3. Check Namespaces
```bash
kubectl get namespaces | grep glucosync

# Should show 6 namespaces:
# glucosync-admin
# glucosync-cicd
# glucosync-core
# glucosync-data
# glucosync-monitoring
# glucosync-services
```

### 4. Check Storage
```bash
kubectl get storageclass
kubectl get pods -n longhorn-system

# StorageClass 'longhorn' should be (default)
# All longhorn-manager pods should be Running
```

### 5. Check cert-manager
```bash
kubectl get pods -n cert-manager

# Should show 3 pods Running:
# cert-manager-xxxxx
# cert-manager-cainjector-xxxxx
# cert-manager-webhook-xxxxx
```

### 6. Check ClusterIssuers
```bash
kubectl get clusterissuer

# Should show:
# NAME                     READY   AGE
# letsencrypt-staging      True    Xm
# letsencrypt-production   True    Xm
```

### 7. Verify Cloudflare Secret
```bash
kubectl get secret cloudflare-api-token -n cert-manager

# Should exist with age Xm
```

### 8. Check Nginx Ingress
```bash
kubectl get svc -n ingress-nginx

# Should show external IP: 161.97.160.177
```

### 9. Check Security Status
```bash
# Firewall
sudo ufw status

# Should show allowed ports:
# 22, 80, 443, 6443, 2379:2380, 10250-10252, etc.

# Fail2ban
sudo fail2ban-client status

# Should show active jails: sshd, sshd-ddos, k3s-api
```

---

## 🧪 Test Certificate Issuance

### Apply ClusterIssuer
```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
cd /home/admin/ServerInfrastructure/glucosync-k8s

kubectl apply -f k8s/base/networking/cert-manager/cluster-issuer.yaml
```

### Test with Longhorn Ingress
```bash
# Apply longhorn ingress (includes certificate)
kubectl apply -f k8s/base/storage/longhorn/settings.yaml

# Watch certificate issuance (takes 1-3 minutes)
watch kubectl get certificate -n longhorn-system

# Expected result:
# NAME           READY   SECRET         AGE
# longhorn-tls   True    longhorn-tls   2m
```

### Check for Issues
```bash
# If certificate is not ready, check:
kubectl describe certificate longhorn-tls -n longhorn-system
kubectl get challenge -A
kubectl logs -n cert-manager -l app=cert-manager --tail=50
```

---

## 🎯 Success Criteria

Your setup is successful when:

- [ ] ✅ All pods in all namespaces are Running
- [ ] ✅ StorageClass 'longhorn' exists and is default
- [ ] ✅ Both ClusterIssuers show READY=True
- [ ] ✅ Cloudflare secret exists in cert-manager namespace
- [ ] ✅ Nginx Ingress has external IP 161.97.160.177
- [ ] ✅ Test certificate issued successfully (longhorn-tls)
- [ ] ✅ Security hardening complete (fail2ban, UFW, SSH locked down)
- [ ] ✅ Can access https://longhorn.glucosync.io (after DNS propagation)

---

## 🐛 Troubleshooting

### Issue: Certificate Not Issuing

**Check 1**: Verify secret exists
```bash
kubectl get secret cloudflare-api-token -n cert-manager
```

**Check 2**: Verify ClusterIssuer configuration
```bash
kubectl describe clusterissuer letsencrypt-staging
```

**Check 3**: Check challenges
```bash
kubectl get challenge -A
kubectl describe challenge <challenge-name> -n <namespace>
```

**Check 4**: Check cert-manager logs
```bash
kubectl logs -n cert-manager -l app=cert-manager -f
```

**Common fixes**:
- Wrong API token: Recreate secret with correct token
- DNS not propagated: Wait 5-10 minutes
- Rate limit: Use staging issuer first

### Issue: Ingress Not Accessible

**Check 1**: DNS resolution
```bash
dig longhorn.glucosync.io +short
# Should return Cloudflare IPs or 161.97.160.177
```

**Check 2**: Ingress exists
```bash
kubectl get ingress -A
kubectl describe ingress longhorn-ingress -n longhorn-system
```

**Check 3**: Nginx Ingress logs
```bash
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -f
```

**Check 4**: Firewall
```bash
sudo ufw status | grep -E "80|443"
# Should show allowed
```

### Issue: Pods Not Starting

**Check 1**: Events
```bash
kubectl get events -A --sort-by='.lastTimestamp'
```

**Check 2**: Pod logs
```bash
kubectl logs <pod-name> -n <namespace>
```

**Check 3**: Storage
```bash
kubectl get pv
kubectl get pvc -A
```

---

## 📞 Quick Reference Commands

```bash
# Set kubeconfig (always run first)
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Check everything
kubectl get all -A

# Check certificates
kubectl get certificate -A

# Check secrets
kubectl get secrets -A | grep -E "cloudflare|mongodb|redis|minio"

# Restart cert-manager (if needed)
kubectl rollout restart deployment -n cert-manager

# Check logs
kubectl logs -n cert-manager -l app=cert-manager --tail=50
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=50

# Run security scan
sudo /usr/local/bin/glucosync-security-scan.sh
```

---

## 📚 Next Steps After Successful Setup

1. **Set up basic auth for Longhorn UI**
   ```bash
   apt-get install apache2-utils
   htpasswd -c auth admin
   kubectl -n longhorn-system create secret generic longhorn-basic-auth --from-file=auth
   ```

2. **Deploy databases**
   ```bash
   cd /home/admin/ServerInfrastructure/glucosync-k8s/scripts
   sudo ./deploy-databases.sh
   ```

3. **Deploy your applications**
   - Apply application manifests from `k8s/base/applications/`
   - Each will automatically get HTTPS via cert-manager

4. **Configure monitoring**
   - Deploy Prometheus and Grafana
   - Access via https://grafana.glucosync.io

5. **Set up CI/CD**
   - Deploy ArgoCD
   - Configure GitOps workflows

---

## 🔒 Security Notes

After setup, your server will have:
- ✅ Fail2ban protecting SSH and K3s API
- ✅ UFW firewall with only required ports open
- ✅ SSH hardened (no password auth, rate limited)
- ✅ Automatic security updates enabled
- ✅ System auditing active
- ✅ AppArmor enabled
- ✅ File integrity monitoring (AIDE)
- ✅ Daily security scans

**Remember**:
- Keep your Cloudflare API token secure
- Store all passwords in a password manager
- Regularly check security scan logs: `/var/log/glucosync-security.log`
- Run Lynis audit monthly: `sudo lynis audit system`

---

## 📝 Summary

**You are now ready to:**
1. Reset your VPS to Ubuntu 22.04
2. Upload the fixed glucosync-k8s directory
3. Run `sudo ./cluster-setup.sh` and select option 9
4. Enter your credentials when prompted
5. Wait 15-25 minutes for complete setup
6. Verify everything is working
7. Start deploying your applications!

**All fixes are applied and ready to go! 🚀**

---

**Last Updated**: February 9, 2026  
**Script Version**: 2.2 (cert-manager namespace fix)  
**Server IP**: 161.97.160.177  
**Domain**: glucosync.io
