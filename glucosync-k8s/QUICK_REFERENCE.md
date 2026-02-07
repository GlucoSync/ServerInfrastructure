# GlucoSync Kubernetes Quick Reference

## Essential Commands

### Cluster Management

```bash
# Check cluster health
kubectl get nodes
kubectl get pods -A
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20

# Get cluster info
kubectl cluster-info
kubectl version

# View cluster resources
kubectl top nodes
kubectl top pods -A
```

### Application Management

```bash
# Check GlucoEngine status
kubectl get pods -n glucosync-core -l app=glucoengine
kubectl logs -n glucosync-core -l app=glucoengine --tail=50 -f
kubectl describe deployment glucoengine -n glucosync-core

# Scale GlucoEngine
kubectl scale deployment glucoengine -n glucosync-core --replicas=5

# Restart GlucoEngine (rolling)
kubectl rollout restart deployment glucoengine -n glucosync-core

# Check rollout status
kubectl rollout status deployment glucoengine -n glucosync-core

# Rollback deployment
kubectl rollout undo deployment glucoengine -n glucosync-core
```

### Database Operations

```bash
# MongoDB
kubectl exec -it mongodb-0 -n glucosync-data -- mongo admin -u admin -p PASSWORD
kubectl logs -n glucosync-data mongodb-0 -f

# Redis
kubectl exec -it redis-0 -n glucosync-data -- redis-cli
kubectl exec -it redis-0 -n glucosync-data -- redis-cli INFO stats

# PostgreSQL
kubectl exec -it authentik-postgres-0 -n glucosync-data -- psql -U postgres
```

### Monitoring

```bash
# Port forward Grafana
kubectl port-forward -n glucosync-monitoring svc/grafana 3000:3000
# Access: http://localhost:3000

# Port forward Prometheus
kubectl port-forward -n glucosync-monitoring svc/prometheus 9090:9090
# Access: http://localhost:9090

# View Prometheus targets
kubectl port-forward -n glucosync-monitoring svc/prometheus 9090:9090
# Then visit: http://localhost:9090/targets
```

### Debugging

```bash
# Get shell in pod
kubectl exec -it <POD_NAME> -n <NAMESPACE> -- /bin/sh

# Copy files from pod
kubectl cp <NAMESPACE>/<POD>:/path/to/file ./local-file

# Copy files to pod
kubectl cp ./local-file <NAMESPACE>/<POD>:/path/to/file

# View pod events
kubectl describe pod <POD_NAME> -n <NAMESPACE>

# View previous container logs (after crash)
kubectl logs <POD_NAME> -n <NAMESPACE> --previous
```

### Networking

```bash
# Check ingress
kubectl get ingress -A
kubectl describe ingress glucoengine -n glucosync-core

# Check services
kubectl get svc -A
kubectl describe svc glucoengine -n glucosync-core

# Check endpoints (pods behind service)
kubectl get endpoints glucoengine -n glucosync-core

# Check certificates
kubectl get certificate -A
kubectl describe certificate glucoengine-tls -n glucosync-core

# Test DNS from within cluster
kubectl run curl-test --image=curlimages/curl -i --tty --rm -- sh
# Then: curl http://glucoengine.glucosync-core.svc.cluster.local
```

### Storage

```bash
# Check PVCs
kubectl get pvc -A

# Check PVs
kubectl get pv

# Describe PVC
kubectl describe pvc <PVC_NAME> -n <NAMESPACE>

# Longhorn volumes
kubectl get volumes -n longhorn-system
```

## Service URLs

| Service | URL | Purpose |
|---------|-----|---------|
| API | https://api.glucosync.io | GlucoEngine backend |
| App | https://app.glucosync.io | NewClient PWA |
| Website | https://glucosync.io | Marketing site |
| Grafana | https://grafana.glucosync.io | Dashboards |
| Prometheus | https://prometheus.glucosync.io | Metrics |
| ArgoCD | https://argocd.glucosync.io | GitOps |
| Gitea | https://git.glucosync.io | Git server |
| Woodpecker | https://ci.glucosync.io | CI/CD |
| Harbor | https://harbor.glucosync.io | Container registry |
| Authentik | https://auth.glucosync.io | SSO |
| MLflow | https://mlflow.glucosync.io | ML tracking |
| Longhorn | https://longhorn.glucosync.io | Storage UI |
| MinIO | https://minio.glucosync.io | Object storage |

## Common Troubleshooting

### Pod Won't Start

```bash
# 1. Check pod status
kubectl get pod <POD> -n <NAMESPACE>

# 2. Describe pod for events
kubectl describe pod <POD> -n <NAMESPACE>

# 3. Check logs
kubectl logs <POD> -n <NAMESPACE>

# 4. Check previous logs if crashed
kubectl logs <POD> -n <NAMESPACE> --previous

# 5. Common fixes
kubectl delete pod <POD> -n <NAMESPACE>  # Force restart
kubectl rollout restart deployment <DEPLOYMENT> -n <NAMESPACE>
```

### Service Not Accessible

```bash
# 1. Check pods are running
kubectl get pods -n <NAMESPACE> -l app=<APP>

# 2. Check service endpoints
kubectl get endpoints <SERVICE> -n <NAMESPACE>

# 3. Check ingress
kubectl get ingress <INGRESS> -n <NAMESPACE>
kubectl describe ingress <INGRESS> -n <NAMESPACE>

# 4. Check certificate
kubectl get certificate -n <NAMESPACE>
kubectl describe certificate <CERT> -n <NAMESPACE>

# 5. Test from within cluster
kubectl run curl-test --image=curlimages/curl -i --tty --rm -- \
  curl http://<SERVICE>.<NAMESPACE>.svc.cluster.local
```

### High CPU/Memory

```bash
# 1. Check resource usage
kubectl top pods -n <NAMESPACE>

# 2. Check limits
kubectl describe pod <POD> -n <NAMESPACE> | grep -A 5 Limits

# 3. Scale up
kubectl scale deployment <DEPLOYMENT> -n <NAMESPACE> --replicas=<N>

# 4. Increase resources
kubectl set resources deployment <DEPLOYMENT> -n <NAMESPACE> \
  --limits=cpu=2000m,memory=2Gi \
  --requests=cpu=500m,memory=1Gi
```

### Database Connection Issues

```bash
# MongoDB
kubectl exec -it mongodb-0 -n glucosync-data -- \
  mongo --eval "rs.status()"

# Redis
kubectl exec -it redis-0 -n glucosync-data -- \
  redis-cli PING

# PostgreSQL
kubectl exec -it authentik-postgres-0 -n glucosync-data -- \
  psql -U postgres -c "SELECT 1"

# Test from app pod
kubectl exec -it <APP_POD> -n glucosync-core -- \
  nc -zv mongodb-client.glucosync-data.svc.cluster.local 27017
```

## Backup & Restore

### MongoDB Backup

```bash
# Manual backup
./scripts/backup-restore.sh
# Select option 1

# Check backups in MinIO
mc ls minio/mongodb-backups/
```

### MongoDB Restore

```bash
# Restore from backup
./scripts/backup-restore.sh
# Select option 2
# Provide backup file path
```

### Velero Backup

```bash
# Create backup
velero backup create glucosync-backup-$(date +%Y%m%d-%H%M%S) \
  --include-namespaces glucosync-core,glucosync-data,glucosync-services

# List backups
velero backup get

# Restore
velero restore create --from-backup <BACKUP_NAME>
```

## CI/CD

### Trigger Build

```bash
# Push to Gitea triggers automatic build
git push origin main

# View pipeline in Woodpecker
# https://ci.glucosync.io
```

### Manual Deploy with ArgoCD

```bash
# Sync application
argocd app sync glucoengine

# List applications
argocd app list

# Get application details
argocd app get glucoengine

# Hard refresh
argocd app get glucoengine --hard-refresh
```

## Scaling

### Horizontal Pod Autoscaling

```bash
# Check HPA status
kubectl get hpa -n glucosync-core

# Describe HPA
kubectl describe hpa glucoengine -n glucosync-core

# Manually scale (overrides HPA)
kubectl scale deployment glucoengine -n glucosync-core --replicas=7
```

### Add Worker Node

```bash
# On new node
export K3S_URL="https://<CONTROL_PLANE_IP>:6443"
export K3S_TOKEN="<TOKEN>"
curl -sfL https://get.k3s.io | K3S_URL=$K3S_URL K3S_TOKEN=$K3S_TOKEN sh -

# Verify from control plane
kubectl get nodes
```

## Useful Aliases

Add to `~/.bashrc` or `~/.zshrc`:

```bash
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgi='kubectl get ingress'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias kx='kubectl exec -it'
alias kns='kubectl config set-context --current --namespace'

# GlucoSync specific
alias gluco-pods='kubectl get pods -n glucosync-core'
alias gluco-logs='kubectl logs -n glucosync-core -l app=glucoengine -f --tail=100'
alias gluco-db='kubectl exec -it mongodb-0 -n glucosync-data -- mongo admin -u admin'

# Quick health check
alias health='kubectl get nodes && kubectl get pods -A | grep -v Running | grep -v Completed'
```

## Emergency Contacts

| Role | Contact |
|------|---------|
| Primary On-Call | TBD |
| Backup On-Call | TBD |
| Team Lead | TBD |
| Management | TBD |

## Important File Locations

```
/var/lib/rancher/k3s/server/node-token    # K3s join token (control plane)
/etc/rancher/k3s/k3s.yaml                 # Kubeconfig file
/var/lib/rancher/k3s/agent/                # K3s agent data (worker)
/var/lib/longhorn/                         # Longhorn storage
~/.kube/config                             # Kubectl config
```

## Port Reference

| Port | Service | Purpose |
|------|---------|---------|
| 6443 | K8s API | Kubernetes API server |
| 10250 | Kubelet | Kubelet API |
| 30080 | HTTP | Nginx Ingress NodePort |
| 30443 | HTTPS | Nginx Ingress NodePort |
| 8404 | HAProxy | HAProxy stats page |
| 27017 | MongoDB | MongoDB default port |
| 6379 | Redis | Redis default port |
| 5432 | PostgreSQL | PostgreSQL default port |

## Resource Requests/Limits Reference

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|-------------|-----------|----------------|--------------|
| GlucoEngine | 500m | 2000m | 1Gi | 2Gi |
| MainWebsite | 100m | 500m | 128Mi | 256Mi |
| NewClient | 100m | 500m | 128Mi | 256Mi |
| MongoDB | 500m | 2000m | 2Gi | 4Gi |
| Redis | 200m | 1000m | 2Gi | 3Gi |
| PostgreSQL | 500m | 2000m | 1Gi | 2Gi |
| Nginx Ingress | 200m | 1000m | 256Mi | 512Mi |
| Prometheus | 500m | 2000m | 2Gi | 4Gi |
| Grafana | 200m | 1000m | 512Mi | 1Gi |

## Related Documentation

- [README.md](README.md) - Getting started guide
- [DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md) - Full deployment checklist
- [docs/architecture.md](docs/architecture.md) - Architecture documentation
- [docs/runbooks/disaster-recovery.md](docs/runbooks/disaster-recovery.md) - DR procedures
- [docs/runbooks/troubleshooting.md](docs/runbooks/troubleshooting.md) - Troubleshooting guide
