# GlucoSync Kubernetes Infrastructure

Production-grade Kubernetes infrastructure for GlucoSync diabetes management platform with zero-downtime deployments, high availability, and comprehensive observability.

## 🚀 Quick Start (NixOS)

### Prerequisites
- 1-4 servers (1 control plane + 0-3 optional workers)
- NixOS 23.11+ or ability to install Nix
- 8 CPU cores, 16GB RAM, 500GB SSD per node (control plane)
- 4 CPU cores, 8GB RAM, 200GB SSD per node (workers)
- Root SSH access to all nodes
- Cloudflare account (for DNS and SSL)

### Deployment Options

#### Option 1: Single-Node Cluster (Simplest)
Perfect for development, testing, or small deployments. Everything runs on one server.

```bash
cd glucosync-k8s

# Run the deployment script (it will auto-enter nix dev shell if needed)
./scripts/deploy-cluster-nix.sh
# When prompted, choose "no" for workers
```

**Alternative: Using nix develop explicitly**
```bash
cd glucosync-k8s
nix develop  # Enter development shell with all tools

./scripts/deploy-cluster-nix.sh
```

#### Option 2: Multi-Node Cluster (Production)
High availability setup with dedicated worker nodes for better resource isolation and scaling.

```bash
cd glucosync-k8s

# Deploy with workers (script auto-enters nix dev shell)
./scripts/deploy-cluster-nix.sh
# When prompted:
# - Enter control plane IP
# - Choose "yes" for workers
# - Provide worker IPs (1-3 nodes)
```

#### Option 3: Manual Deployment (Advanced)
```bash
# Deploy control plane (includes HAProxy)
export CONTROL_PLANE_IP="192.168.1.10"
nixos-rebuild switch \
    --flake .#glucosync-control-plane \
    --target-host "root@$CONTROL_PLANE_IP" \
    --build-host localhost

# Optionally deploy workers
export WORKER1_IP="192.168.1.11"
nixos-rebuild switch \
    --flake .#glucosync-worker \
    --target-host "root@$WORKER1_IP" \
    --build-host localhost
```

### What Gets Deployed

The deployment script automatically:
- ✅ Installs K3s control plane with embedded HAProxy
- ✅ Creates all namespaces
- ✅ Installs Longhorn storage
- ✅ Installs cert-manager
- ✅ Installs Nginx Ingress Controller
- ✅ Installs Postgres Operator
- ✅ Installs Prometheus & Grafana monitoring
- ✅ Installs ArgoCD for GitOps
- ✅ Installs Sealed Secrets
- ✅ Joins worker nodes (if specified)

### Deploy Databases
```bash
./scripts/deploy-databases.sh
```

### Deploy Applications
```bash
kubectl apply -f k8s/base/applications/glucoengine/
kubectl apply -f k8s/base/applications/mainwebsite/
kubectl apply -f k8s/base/applications/newclient/
```

## 🌐 DNS Configuration

### Required DNS Records

Point all DNS records to your **Control Plane IP** (which runs HAProxy):

```
# A Records (point to Control Plane IP)
glucosync.io                  A     <CONTROL_PLANE_IP>
*.glucosync.io                A     <CONTROL_PLANE_IP>

# Or individual records
api.glucosync.io              A     <CONTROL_PLANE_IP>
app.glucosync.io              A     <CONTROL_PLANE_IP>
grafana.glucosync.io          A     <CONTROL_PLANE_IP>
prometheus.glucosync.io       A     <CONTROL_PLANE_IP>
argocd.glucosync.io           A     <CONTROL_PLANE_IP>
git.glucosync.io              A     <CONTROL_PLANE_IP>
harbor.glucosync.io           A     <CONTROL_PLANE_IP>
auth.glucosync.io             A     <CONTROL_PLANE_IP>
mlflow.glucosync.io           A     <CONTROL_PLANE_IP>
```

## 📁 Directory Structure

```
glucosync-k8s/
├── k8s/                           # Kubernetes manifests
│   ├── base/                      # Base configurations
│   │   ├── namespaces/            # Namespace definitions
│   │   ├── storage/               # Longhorn, MinIO
│   │   ├── networking/            # Nginx Ingress, cert-manager
│   │   ├── databases/             # MongoDB, Redis, PostgreSQL
│   │   ├── applications/          # GlucoEngine, websites
│   │   ├── services/              # Authentik, Mailu, MLflow
│   │   ├── cicd/                  # Gitea, Woodpecker, ArgoCD, Harbor
│   │   ├── monitoring/            # Prometheus, Grafana, Loki, Tempo
│   │   └── admin/                 # Admin UIs
│   └── overlays/                  # Environment-specific overrides
│       ├── development/
│       ├── staging/
│       └── production/
├── infrastructure/
│   ├── ansible/                   # Server provisioning
│   └── haproxy/                   # Load balancer config
├── docker/                        # Application Dockerfiles
│   ├── glucoengine/               # Backend API
│   ├── mainwebsite/               # Marketing site
│   └── newclient/                 # PWA client
├── ci-cd/                         # CI/CD pipeline configs
│   └── woodpecker/                # Woodpecker CI templates
├── monitoring/                    # Dashboards and alerts
│   ├── dashboards/                # Grafana dashboards
│   └── alerts/                    # Prometheus alert rules
├── scripts/                       # Automation scripts
│   ├── cluster-setup.sh           # Cluster initialization
│   ├── deploy-databases.sh        # Database deployment
│   └── backup-restore.sh          # Backup/restore utilities
└── docs/                          # Documentation
    ├── runbooks/                  # Operational procedures
    │   ├── disaster-recovery.md   # DR procedures
    │   └── troubleshooting.md     # Common issues
    └── architecture.md            # Architecture documentation
```

## 🏗️ Architecture Overview

### Single-Node Mode
```
Internet → Cloudflare DNS → Control Plane Server
                                ↓
                          K3s + HAProxy
                                ↓
                     Nginx Ingress Controller
                                ↓
                    All Applications & Services
```

### Multi-Node Mode
```
Internet → Cloudflare DNS → Control Plane (HAProxy)
                                ↓
                     Kubernetes Cluster (K3s)
                                ↓
                     Nginx Ingress Controller
                                ↓
         ┌──────────────────────┼──────────────────────┐
         ↓                      ↓                      ↓
     Worker Node 1         Worker Node 2         Worker Node 3
     (2-3 replicas of each application/service)
```

### Namespaces
- **glucosync-core**: Backend (GlucoEngine), Frontend (MainWebsite, NewClient)
- **glucosync-data**: Databases (MongoDB, Redis, PostgreSQL)
- **glucosync-services**: Authentik, Mailu, MLflow
- **glucosync-cicd**: Gitea, Woodpecker, ArgoCD, Harbor
- **glucosync-monitoring**: Prometheus, Grafana, Loki, Tempo, Alertmanager
- **glucosync-admin**: mongo-express, redis-commander, pgAdmin

## 🗄️ Database Architecture

### MongoDB (3-Node Replica Set)
- **Purpose:** Primary application database
- **HA:** 1 primary + 2 secondary, automatic failover (< 30s)
- **Backups:** Every 6 hours to MinIO, 30-day retention
- **Connection:** `mongodb://mongodb-client.glucosync-data.svc.cluster.local:27017/glucosync?replicaSet=rs0`

### Redis (3-Node Sentinel)
- **Purpose:** Caching, sessions, rate limiting
- **HA:** Sentinel quorum 2/3, automatic failover (< 15s)
- **Persistence:** AOF + RDB snapshots

### PostgreSQL (Zalando Operator)
- **Clusters:**
  - `authentik-postgres`: SSO database
  - `gitea-postgres`: Git server database
  - `mlflow-postgres`: ML metadata
- **HA:** 2-node streaming replication, Patroni automatic failover

## 🚢 Deployment Strategy

### Zero-Downtime Rolling Updates
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1        # Create 1 extra pod
    maxUnavailable: 0  # Never go below desired count
```

### Auto-Scaling
- **GlucoEngine:** 3-10 replicas (CPU > 70%)
- **Nginx Ingress:** 3-10 replicas (CPU > 70%)

### Pod Disruption Budgets
- **GlucoEngine:** Minimum 2 pods available during disruptions
- **MongoDB:** Minimum 2 pods for quorum
- **Redis:** Minimum 2 pods for Sentinel quorum

## 🔄 CI/CD Pipeline

```
Developer Push → Gitea → Webhook → Woodpecker CI
                                        ↓
                            Build & Test & Scan Image
                                        ↓
                            Push to Harbor Registry
                                        ↓
                            Update GitOps Repo (manifest)
                                        ↓
                            ArgoCD Auto-Sync
                                        ↓
                            Rolling Update in Kubernetes
                                        ↓
                            Health Checks → Success/Rollback
```

### Setup CI/CD
1. **Install Gitea:**
   ```bash
   kubectl apply -f k8s/base/cicd/gitea/
   ```

2. **Install Woodpecker:**
   ```bash
   kubectl apply -f k8s/base/cicd/woodpecker/
   ```

3. **Install ArgoCD:**
   ```bash
   kubectl create namespace argocd
   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   kubectl apply -f k8s/base/cicd/argocd/
   ```

4. **Install Harbor:**
   ```bash
   helm repo add harbor https://helm.goharbor.io
   helm install harbor harbor/harbor -n glucosync-cicd -f k8s/base/cicd/harbor/values.yaml
   ```

## 📊 Monitoring & Observability

### Grafana Dashboards
- **Cluster Overview:** Node health, pod distribution, resource usage
- **GlucoEngine Dashboard:** Request rate, error rate, response times
- **Database Performance:** MongoDB/Redis/PostgreSQL metrics
- **Business Metrics:** User signups, glucose readings, ML predictions

### Access Monitoring
```bash
# Grafana
https://grafana.glucosync.io
# Login with Authentik SSO

# Prometheus
https://prometheus.glucosync.io

# Loki (via Grafana)
# Navigate to Explore → Select Loki data source
```

### Custom Metrics (GlucoEngine)
```typescript
// Add to your NestJS application
import { Counter, Histogram, Gauge } from 'prom-client';

// Define metrics
const glucoseReadingsCounter = new Counter({
  name: 'glucosync_glucose_readings_total',
  help: 'Total number of glucose readings ingested'
});

const mlPredictionsCounter = new Counter({
  name: 'glucosync_ml_predictions_total',
  help: 'Total number of ML predictions generated'
});

const apiDurationHistogram = new Histogram({
  name: 'glucosync_api_request_duration_seconds',
  help: 'API request duration in seconds',
  labelNames: ['method', 'endpoint', 'status']
});

const activeWebSocketConnections = new Gauge({
  name: 'glucosync_active_websocket_connections',
  help: 'Number of active WebSocket connections'
});
```

## 🔒 Security

### SSL/TLS Certificates
- **Automated:** cert-manager with Let's Encrypt
- **DNS Challenge:** Cloudflare DNS-01
- **Auto-renewal:** 30 days before expiry

```bash
# Create Cloudflare API token secret
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token=YOUR_CLOUDFLARE_TOKEN

# Apply cluster issuer
kubectl apply -f k8s/base/networking/cert-manager/cluster-issuer.yaml
```

### Secrets Management
```bash
# Install Sealed Secrets
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# Create sealed secret
kubectl create secret generic my-secret \
  --from-literal=password=supersecret \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > my-sealed-secret.yaml

# Commit sealed secret to Git
git add my-sealed-secret.yaml
git commit -m "Add sealed secret"
```

### Network Policies
```bash
# Install Calico
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/calico.yaml

# Apply network policies (coming soon)
kubectl apply -f k8s/base/security/network-policies/
```

## 💾 Backup & Disaster Recovery

### Automated Backups

#### MongoDB
- **Frequency:** Every 6 hours
- **Storage:** MinIO bucket `mongodb-backups`
- **Retention:** 30 days

```bash
# Manual backup
./scripts/backup-restore.sh
# Select option 1: Backup MongoDB
```

#### Velero (Full Cluster)
```bash
# Install Velero
velero install \
  --provider aws \
  --bucket glucosync-backups \
  --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://minio-api.glucosync-data.svc.cluster.local:9000

# Create backup
./scripts/backup-restore.sh
# Select option 4: Create Velero Backup
```

### Restore Procedures
See [Disaster Recovery Runbook](docs/runbooks/disaster-recovery.md) for detailed procedures.

**Quick restore:**
```bash
# Restore MongoDB
./scripts/backup-restore.sh
# Select option 2: Restore MongoDB

# Restore from Velero
./scripts/backup-restore.sh
# Select option 5: Restore from Velero Backup
```

## 🔧 Operations

### Useful Commands

#### Health Check
```bash
# Check all pods
kubectl get pods -A

# Check nodes
kubectl get nodes

# Check ingress
kubectl get ingress -A

# Check certificates
kubectl get certificate -A
```

#### Scale Applications
```bash
# Scale GlucoEngine
kubectl scale deployment glucoengine -n glucosync-core --replicas=5

# Scale Nginx Ingress
kubectl scale deployment ingress-nginx-controller -n ingress-nginx --replicas=5
```

#### View Logs
```bash
# GlucoEngine logs
kubectl logs -n glucosync-core -l app=glucoengine --tail=100 -f

# MongoDB logs
kubectl logs -n glucosync-data mongodb-0 -f

# Ingress logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -f
```

#### Port Forward Services
```bash
# Grafana
kubectl port-forward -n glucosync-monitoring svc/grafana 3000:3000

# MongoDB
kubectl port-forward -n glucosync-data svc/mongodb-client 27017:27017

# ArgoCD
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

### Troubleshooting
See [Troubleshooting Guide](docs/runbooks/troubleshooting.md) for common issues and solutions.

## 📈 Performance Optimization

### Database Indexing
```bash
# Connect to MongoDB
kubectl exec -it mongodb-0 -n glucosync-data -- mongo

# Create indexes
use glucosync
db.users.createIndex({ "email": 1 })
db.glucoseReadings.createIndex({ "userId": 1, "timestamp": -1 })
db.glucoseReadings.createIndex({ "timestamp": -1 })
```

### Redis Cache Tuning
```bash
# Check cache hit ratio
kubectl exec -it redis-0 -n glucosync-data -- \
  redis-cli INFO stats | grep keyspace

# Increase memory if needed
kubectl edit statefulset redis -n glucosync-data
# Update resources.limits.memory
```

### Application Optimization
- Enable Redis caching for frequent queries
- Optimize database queries with indexes
- Use connection pooling
- Implement query result pagination

## 🌐 DNS Configuration

### Required DNS Records

Point all DNS records to your **Control Plane IP** (which runs HAProxy):

```
# A Records (point to Control Plane IP)
glucosync.io                  A     <CONTROL_PLANE_IP>
*.glucosync.io                A     <CONTROL_PLANE_IP>

# Or individual records
api.glucosync.io              A     <CONTROL_PLANE_IP>
app.glucosync.io              A     <CONTROL_PLANE_IP>
grafana.glucosync.io          A     <CONTROL_PLANE_IP>
prometheus.glucosync.io       A     <CONTROL_PLANE_IP>
argocd.glucosync.io           A     <CONTROL_PLANE_IP>
git.glucosync.io              A     <CONTROL_PLANE_IP>
harbor.glucosync.io           A     <CONTROL_PLANE_IP>
auth.glucosync.io             A     <CONTROL_PLANE_IP>
mlflow.glucosync.io           A     <CONTROL_PLANE_IP>

# MX Record (for email)
glucosync.io                  MX    10 mail.glucosync.io

# TXT Records (email authentication)
glucosync.io                  TXT   "v=spf1 mx ~all"
_dmarc.glucosync.io           TXT   "v=DMARC1; p=quarantine; rua=mailto:admin@glucosync.io"
```

## 💻 NixOS Configuration

### Flake Structure
```nix
glucosync-k8s/
├── flake.nix                          # Main flake definition
├── nixos/
│   ├── common.nix                     # Shared config for all nodes
│   ├── control-plane.nix              # Control plane + HAProxy
│   ├── worker.nix                     # Worker nodes
│   ├── hardware-configuration.nix     # Hardware-specific config
│   └── modules/
│       ├── k3s-server.nix             # K3s server configuration
│       ├── k3s-agent.nix              # K3s agent configuration
│       └── security.nix               # Security hardening
```

### Development Shell
The flake provides a development shell with all necessary tools:

```bash
nix develop

# Available tools:
# - kubectl, helm, k9s, kubectx, kustomize
# - argocd, velero
# - docker, docker-compose
# - prometheus, grafana
# - minio-client (mc)
```

### Updating the Cluster

```bash
# Update control plane
nixos-rebuild switch \
    --flake .#glucosync-control-plane \
    --target-host "root@<CONTROL_PLANE_IP>" \
    --build-host localhost

# Update all workers
for ip in 192.168.1.11 192.168.1.12; do
    nixos-rebuild switch \
        --flake .#glucosync-worker \
        --target-host "root@$ip" \
        --build-host localhost
done
```

## 🎯 Migration from Docker Compose

### Pre-Migration Checklist
- [ ] Kubernetes cluster deployed and healthy
- [ ] All databases deployed with replication
- [ ] Applications deployed and accessible
- [ ] Monitoring stack operational
- [ ] Backups configured and tested
- [ ] SSL certificates issued
- [ ] DNS records ready (not yet pointed)

### Migration Steps

1. **Backup Docker Compose Data**
   ```bash
   # MongoDB
   docker exec mongodb mongodump --out=/backup

   # Copy backup files
   docker cp mongodb:/backup ./mongodb-backup
   ```

2. **Import to Kubernetes**
   ```bash
   # Copy backup to Kubernetes
   kubectl cp ./mongodb-backup glucosync-data/mongodb-0:/tmp/backup

   # Restore
   kubectl exec -it mongodb-0 -n glucosync-data -- \
     mongorestore /tmp/backup
   ```

3. **Update DNS** (during maintenance window)
   ```bash
   # Update A records to point to HAProxy
   # TTL should be low (300s) for quick rollback
   ```

4. **Monitor** (24/7 for first week)
   - Check Grafana dashboards
   - Monitor error rates
   - Verify all features working

5. **Rollback Plan** (if issues)
   ```bash
   # Revert DNS to Docker Compose
   # Keep Kubernetes running for diagnosis
   ```

6. **Decommission Docker Compose** (after 1 month)

## 📚 Documentation

- [Architecture Documentation](docs/architecture.md) - Detailed system architecture
- [Disaster Recovery Runbook](docs/runbooks/disaster-recovery.md) - DR procedures
- [Troubleshooting Guide](docs/runbooks/troubleshooting.md) - Common issues and solutions

## 🤝 Contributing

1. Create feature branch: `git checkout -b feature/my-feature`
2. Make changes and test locally
3. Commit: `git commit -m "Add my feature"`
4. Push: `git push origin feature/my-feature`
5. Create Pull Request

## 📝 License

Proprietary - GlucoSync Platform

## 🆘 Support

- **Documentation:** [docs/](docs/)
- **Issues:** Create issue in Gitea
- **Slack:** #glucosync-support
- **On-Call:** See [Emergency Contacts](docs/runbooks/disaster-recovery.md#emergency-contacts)

## ✅ Success Criteria

- ✅ Zero downtime during deployments
- ✅ < 30 second database failover time
- ✅ < 2 second API response time (p95)
- ✅ 99.9% uptime (< 43 minutes downtime/month)
- ✅ Automated SSL certificate renewal
- ✅ All services monitored with alerts
- ✅ Full backup and restore capability
- ✅ CI/CD pipeline functional with < 10 minute build time
- ✅ Security best practices implemented
- ✅ Comprehensive documentation for operations
