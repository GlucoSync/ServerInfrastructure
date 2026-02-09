# GlucoSync Cloudflare DNS Setup Guide

## Overview

This guide covers the complete Cloudflare DNS configuration for your GlucoSync Kubernetes cluster. Your cluster is running at IP: **161.97.160.177**

## Prerequisites

- ✅ K3s cluster installed and running
- ✅ Nginx Ingress Controller installed
- ✅ cert-manager installed
- ✅ Cloudflare API token created (should be stored in Kubernetes already)
- 🔧 Domain registered with Cloudflare (glucosync.io)

## Step 1: Get Your Ingress Controller External IP

First, verify the external IP of your Nginx Ingress Controller:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get svc -n ingress-nginx
```

You should see something like:
```
NAME                                 TYPE           CLUSTER-IP      EXTERNAL-IP       PORT(S)
ingress-nginx-controller             LoadBalancer   10.43.x.x       161.97.160.177    80:xxxxx/TCP,443:xxxxx/TCP
```

Your external IP is: **161.97.160.177**

## Step 2: Cloudflare DNS Records

Log into your Cloudflare dashboard and add the following DNS records for `glucosync.io`:

### Required A Records

| Type | Name         | Content          | Proxy Status | TTL  | Priority |
|------|--------------|------------------|--------------|------|----------|
| A    | @            | 161.97.160.177   | ☁️ Proxied   | Auto | -        |
| A    | www          | 161.97.160.177   | ☁️ Proxied   | Auto | -        |
| A    | api          | 161.97.160.177   | ☁️ Proxied   | Auto | -        |
| A    | auth         | 161.97.160.177   | ☁️ Proxied   | Auto | -        |
| A    | longhorn     | 161.97.160.177   | ☁️ Proxied   | Auto | -        |
| A    | grafana      | 161.97.160.177   | ☁️ Proxied   | Auto | -        |
| A    | prometheus   | 161.97.160.177   | ☁️ Proxied   | Auto | -        |
| A    | argocd       | 161.97.160.177   | ☁️ Proxied   | Auto | -        |
| A    | git          | 161.97.160.177   | ☁️ Proxied   | Auto | -        |
| A    | ci           | 161.97.160.177   | ☁️ Proxied   | Auto | -        |
| A    | mlflow       | 161.97.160.177   | ☁️ Proxied   | Auto | -        |

### CLI Method (Using Cloudflare API)

If you prefer to use the API, here's a script:

```bash
#!/bin/bash
# Set your Cloudflare credentials
CLOUDFLARE_API_TOKEN="your-api-token-here"
ZONE_ID="your-zone-id-here"  # Get from Cloudflare dashboard
IP="161.97.160.177"

# Domains to create
DOMAINS=(
  "@"
  "www"
  "api"
  "auth"
  "longhorn"
  "grafana"
  "prometheus"
  "argocd"
  "git"
  "ci"
  "mlflow"
)

for domain in "${DOMAINS[@]}"; do
  echo "Creating DNS record for: $domain"
  curl -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "{
      \"type\": \"A\",
      \"name\": \"$domain\",
      \"content\": \"${IP}\",
      \"ttl\": 1,
      \"proxied\": true
    }"
done
```

## Step 3: Cloudflare Settings for Kubernetes

### SSL/TLS Settings

1. Go to **SSL/TLS** → **Overview**
2. Set encryption mode to: **Full (strict)**
   - This ensures end-to-end encryption between Cloudflare and your cluster

### SSL/TLS Edge Certificates

1. Go to **SSL/TLS** → **Edge Certificates**
2. Enable:
   - ✅ Always Use HTTPS
   - ✅ HTTP Strict Transport Security (HSTS)
   - ✅ Minimum TLS Version: TLS 1.2
   - ✅ Opportunistic Encryption
   - ✅ TLS 1.3

### Firewall Rules (Optional but Recommended)

Create firewall rules to protect your services:

1. Go to **Security** → **WAF** → **Firewall rules**
2. Add rule: **Block known bots**
   - Expression: `(cf.client.bot)`
   - Action: Challenge

3. Add rule: **Rate limiting**
   - Expression: `(http.request.uri.path contains "/api/")`
   - Action: Rate limit (10 requests per minute)

### Page Rules (Optional)

For better caching and performance:

1. Go to **Rules** → **Page Rules**
2. Add rule for `www.glucosync.io/*`:
   - Cache Level: Standard
   - Browser Cache TTL: 4 hours
   - Always Online: On

## Step 4: Create Cloudflare API Token for cert-manager

If you haven't created the API token yet:

1. Go to **My Profile** → **API Tokens**
2. Click **Create Token**
3. Use template: **Edit zone DNS**
4. Configure:
   - **Permissions**:
     - Zone → DNS → Edit
     - Zone → Zone → Read
   - **Zone Resources**:
     - Include → Specific zone → glucosync.io
5. Click **Continue to summary**
6. Click **Create Token**
7. **Save the token** - you won't see it again!

### Add Token to Kubernetes

If not already done during setup:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token=YOUR_TOKEN_HERE \
  --dry-run=client -o yaml | kubectl apply -f -
```

## Step 5: Apply cert-manager ClusterIssuer

This configures cert-manager to use Let's Encrypt with Cloudflare DNS validation:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
cd /home/admin/ServerInfrastructure/glucosync-k8s

# Apply the ClusterIssuer
kubectl apply -f k8s/base/networking/cert-manager/cluster-issuer.yaml
```

Verify it was created:

```bash
kubectl get clusterissuer
```

Expected output:
```
NAME                     READY   AGE
letsencrypt-staging      True    Xs
letsencrypt-production   True    Xs
```

## Step 6: Test DNS Resolution

Wait a few minutes for DNS propagation, then test:

```bash
# Test from your local machine
dig glucosync.io +short
dig api.glucosync.io +short
dig auth.glucosync.io +short
dig longhorn.glucosync.io +short

# Or use nslookup
nslookup api.glucosync.io
```

All should return: **161.97.160.177** (or Cloudflare proxy IPs if proxied)

## Step 7: Test HTTPS Certificate Issuance

Create a test ingress to verify cert-manager is working:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
  namespace: default
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-staging
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - test.glucosync.io
    secretName: test-tls
  rules:
  - host: test.glucosync.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kubernetes
            port:
              number: 443
EOF
```

**Note**: Make sure to add `test.glucosync.io` A record pointing to 161.97.160.177 in Cloudflare first!

Check certificate status:

```bash
kubectl get certificate -n default
kubectl describe certificate test-tls -n default
```

After a few minutes, you should see:
```
NAME       READY   SECRET     AGE
test-tls   True    test-tls   2m
```

If successful, clean up:

```bash
kubectl delete ingress test-ingress -n default
```

## Step 8: Deploy Applications with Ingress

Now you can deploy applications with automatic HTTPS! Here's an example:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app-ingress
  namespace: glucosync-core
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-production
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - api.glucosync.io
    secretName: api-tls
  rules:
  - host: api.glucosync.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-api-service
            port:
              number: 8080
```

## Verification Checklist

- [ ] All DNS A records created in Cloudflare
- [ ] DNS records resolve to 161.97.160.177
- [ ] SSL/TLS mode set to "Full (strict)"
- [ ] Cloudflare API token created and added to Kubernetes
- [ ] ClusterIssuer applied and ready
- [ ] Test certificate issued successfully
- [ ] Can access services via HTTPS

## Troubleshooting

### DNS Not Resolving

```bash
# Check Cloudflare DNS
dig @1.1.1.1 api.glucosync.io

# Flush local DNS cache
# Linux:
sudo systemd-resolve --flush-caches
# macOS:
sudo dscacheutil -flushcache
```

### Certificate Not Issued

```bash
# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager -f

# Check certificate status
kubectl describe certificate <cert-name> -n <namespace>

# Check certificate request
kubectl get certificaterequest -A

# Check challenges
kubectl get challenge -A
```

Common issues:
- **DNS01 challenge failed**: Check Cloudflare API token permissions
- **Rate limited**: Use staging issuer first (`letsencrypt-staging`)
- **Wrong secret name**: Verify `apiTokenSecretRef` in ClusterIssuer

### Ingress Not Working

```bash
# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -f

# Check ingress status
kubectl get ingress -A

# Test from within cluster
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- curl http://my-service.namespace.svc.cluster.local
```

### Cloudflare 522 Error (Connection Timed Out)

- Check firewall allows ports 80 and 443:
  ```bash
  sudo ufw status | grep -E "80|443"
  ```
- Verify nginx ingress is running:
  ```bash
  kubectl get pods -n ingress-nginx
  ```

### Cloudflare 525 Error (SSL Handshake Failed)

- Verify SSL/TLS mode is "Full (strict)"
- Check certificate is valid:
  ```bash
  kubectl get certificate -A
  ```

## Next Steps

1. **Deploy your applications** with ingress resources
2. **Set up monitoring** (Grafana at grafana.glucosync.io)
3. **Configure ArgoCD** (argocd.glucosync.io)
4. **Set up Longhorn UI** (longhorn.glucosync.io) with basic auth
5. **Deploy authentication** (Authentik at auth.glucosync.io)

## Summary of Your Domains

| Domain | Purpose | Ingress Manifest Location |
|--------|---------|---------------------------|
| glucosync.io | Main website | k8s/base/applications/mainwebsite/ |
| www.glucosync.io | WWW redirect | k8s/base/applications/mainwebsite/ |
| api.glucosync.io | API Gateway | k8s/base/applications/glucoengine/ |
| auth.glucosync.io | Authentication (Authentik) | k8s/base/services/authentik/ |
| longhorn.glucosync.io | Storage UI | k8s/base/storage/longhorn/settings.yaml |
| grafana.glucosync.io | Monitoring | k8s/base/monitoring/grafana/ |
| prometheus.glucosync.io | Metrics | k8s/base/monitoring/prometheus/ |
| argocd.glucosync.io | GitOps CD | k8s/base/cicd/argocd/ |
| git.glucosync.io | Git Server (Gitea) | k8s/base/cicd/gitea/ |
| ci.glucosync.io | CI/CD (Woodpecker) | k8s/base/cicd/woodpecker/ |
| mlflow.glucosync.io | ML Tracking | k8s/base/services/mlflow/ |

## Quick Reference Commands

```bash
# Set kubeconfig
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Check DNS from cluster
kubectl run -it --rm dnstest --image=busybox --restart=Never -- nslookup api.glucosync.io

# Check certificates
kubectl get certificate -A

# Check ingress resources
kubectl get ingress -A

# Test HTTPS
curl -v https://api.glucosync.io

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=50
```

---

**Last Updated**: February 2026
**Cluster IP**: 161.97.160.177
**Domain**: glucosync.io
