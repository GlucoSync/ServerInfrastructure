# GlucoSync Kubernetes Architecture Documentation

## System Overview

GlucoSync is a cloud-native diabetes management platform deployed on a multi-server Kubernetes cluster (K3s). The architecture is designed for high availability, scalability, and resilience with zero-downtime deployments.

### High-Level Architecture

```
                                    Internet
                                       │
                                       ▼
                              Cloudflare DNS (CDN)
                                       │
                                       ▼
                            HAProxy (External Load Balancer)
                                       │
                    ┌──────────────────┼──────────────────┐
                    ▼                  ▼                  ▼
              Worker Node 1      Worker Node 2      Worker Node 3
                    │                  │                  │
                    └──────────────────┼──────────────────┘
                                       ▼
                          Nginx Ingress Controller
                                       │
        ┌──────────────┬───────────────┼───────────────┬──────────────┐
        ▼              ▼               ▼               ▼              ▼
    Applications    Databases     Services        CI/CD         Monitoring
    (Core)          (Data)        (Auth/Email)   (GitOps)      (Observability)
```

## Infrastructure Components

### Cluster Configuration

**Control Plane:** 1 node
- K3s lightweight Kubernetes
- etcd (embedded)
- API Server, Scheduler, Controller Manager

**Worker Nodes:** 2-3 nodes
- Application workloads
- Databases (with pod anti-affinity)
- Monitoring stack

**Recommended Node Specs:**
- CPU: 8 cores
- RAM: 16GB
- Storage: 500GB SSD
- OS: Ubuntu 22.04 LTS or Debian 12

### Network Architecture

#### External Load Balancing (HAProxy)
- **Layer 4 & 7 Load Balancing**
- Health checks on `/healthz` endpoint
- Round-robin distribution to worker nodes
- SSL passthrough to Nginx Ingress
- Failover on node failure (< 5 seconds)

#### Internal Routing (Nginx Ingress)
- **TLS Termination** via cert-manager
- Path-based routing to services
- Rate limiting and CORS support
- WebSocket support for real-time features
- Auto-scaling: 3-10 replicas based on CPU

#### Service Mesh
- **Decision:** No service mesh (Istio/Linkerd) initially
- **Rationale:** Small cluster, Nginx Ingress sufficient for L7 routing
- **Future:** Add when scaling beyond 10+ microservices

### Storage Architecture

#### Longhorn (Distributed Block Storage)
- **Purpose:** Persistent volumes for databases and stateful apps
- **Replication:** 3 replicas for databases, 2 for applications
- **Features:**
  - Automatic snapshots
  - Volume backups to S3 (MinIO)
  - Disaster recovery support
  - UI at `longhorn.glucosync.io`

#### MinIO (Object Storage)
- **Purpose:** S3-compatible storage for backups and ML artifacts
- **Deployment:** 4-node distributed setup
- **Buckets:**
  - `mongodb-backups`: Database backups
  - `mlflow-artifacts`: ML model artifacts
  - `longhorn-backups`: Volume snapshots
  - `app-storage`: User uploads

## Application Architecture

### Namespaces

| Namespace | Purpose | Applications |
|-----------|---------|--------------|
| `glucosync-core` | Core applications | GlucoEngine (API), MainWebsite, NewClient (PWA) |
| `glucosync-data` | Databases | MongoDB, Redis, PostgreSQL |
| `glucosync-services` | Supporting services | Authentik (SSO), Mailu (Email), MLflow |
| `glucosync-cicd` | CI/CD pipeline | Gitea, Woodpecker, ArgoCD, Harbor |
| `glucosync-monitoring` | Observability | Prometheus, Grafana, Loki, Tempo |
| `glucosync-admin` | Admin tools | mongo-express, redis-commander, pgAdmin |

### Core Applications

#### GlucoEngine (Backend API)
- **Technology:** NestJS (Node.js)
- **Replicas:** 3-10 (HPA based on CPU 70%)
- **Resources:**
  - Requests: 500m CPU, 1Gi RAM
  - Limits: 2000m CPU, 2Gi RAM
- **Features:**
  - RESTful API
  - WebSocket for real-time updates
  - ML model integration
  - OpenAI GPT integration
- **Deployment Strategy:** Rolling update (maxSurge=1, maxUnavailable=0)
- **Probes:**
  - Liveness: `/health` (30s delay)
  - Readiness: `/health/ready` (10s delay)

#### MainWebsite (Marketing Site)
- **Technology:** Static site (HTML/CSS/JS)
- **Replicas:** 2 (no auto-scaling)
- **Served by:** Nginx
- **Deployment:** Zero-downtime rolling update

#### NewClient (PWA)
- **Technology:** React Progressive Web App
- **Replicas:** 2 (no auto-scaling)
- **Features:**
  - Offline support via service workers
  - Push notifications
  - Add to home screen
- **Deployment:** Zero-downtime rolling update

### Database Architecture

#### MongoDB (3-Node Replica Set)
- **Version:** 7.0
- **Deployment:** StatefulSet with 3 replicas
- **Configuration:**
  - 1 Primary + 2 Secondary
  - Automatic failover (< 30 seconds)
  - Pod anti-affinity (spread across nodes)
- **Persistence:** 50Gi per pod (Longhorn)
- **Backups:**
  - Automated via CronJob (every 6 hours)
  - Stored in MinIO
  - Retention: 30 days
- **Resources:**
  - Requests: 500m CPU, 2Gi RAM
  - Limits: 2000m CPU, 4Gi RAM
- **Connection String:**
  ```
  mongodb://mongodb-client.glucosync-data.svc.cluster.local:27017/glucosync?replicaSet=rs0
  ```

#### Redis (3-Node Sentinel)
- **Version:** 7.2
- **Purpose:** Caching, session storage, rate limiting
- **Deployment:**
  - StatefulSet (3 Redis instances)
  - DaemonSet (3 Sentinel instances)
- **Configuration:**
  - Sentinel quorum: 2 of 3
  - Automatic failover (< 15 seconds)
  - AOF + RDB persistence
  - Eviction policy: `allkeys-lru`
- **Persistence:** 20Gi per pod (Longhorn)
- **Resources:**
  - Redis: 200m CPU, 2Gi RAM
  - Sentinel: 100m CPU, 128Mi RAM

#### PostgreSQL (Zalando Operator)
- **Version:** 15
- **Purpose:** Authentik, Gitea, MLflow metadata
- **Deployment:** 2-node clusters (1 primary + 1 standby)
- **Features:**
  - Streaming replication
  - Automatic failover via Patroni
  - Connection pooling (pgBouncer)
  - WAL archiving for PITR
- **Clusters:**
  - `authentik-postgres`: 20Gi
  - `gitea-postgres`: 10Gi
  - `mlflow-postgres`: 10Gi

### Services

#### Authentik (SSO & Identity Provider)
- **Purpose:** Single Sign-On for all services
- **Deployment:**
  - Server: 2 replicas
  - Worker: 2 replicas
- **Backend:** PostgreSQL + Redis
- **Features:**
  - OAuth2/OIDC provider
  - SAML support
  - LDAP integration
  - MFA support
- **Integrated Services:**
  - Grafana
  - ArgoCD
  - Harbor
  - Gitea
  - MLflow

#### Mailu (Email Server)
- **Components:**
  - Admin UI
  - SMTP server
  - IMAP server
  - Webmail (Roundcube)
  - Anti-spam (Rspamd)
- **DNS Records Required:**
  - MX record
  - SPF record
  - DKIM key
  - DMARC policy
- **Storage:** Persistent volumes for mailboxes

#### MLflow (ML Experiment Tracking)
- **Purpose:** Track ML model experiments and artifacts
- **Backend:** PostgreSQL (metadata)
- **Artifact Store:** MinIO (S3-compatible)
- **Replicas:** 2
- **Integration:** GlucoEngine ML predictions

## CI/CD Architecture

### Git Server (Gitea)
- **Purpose:** Self-hosted Git repository management
- **Backend:** PostgreSQL + Redis
- **Features:**
  - GitHub-like interface
  - Webhook support
  - SSO via Authentik
  - LFS support
- **Storage:** 50Gi for repositories

### CI/CD Pipeline (Woodpecker)
- **Purpose:** Kubernetes-native CI/CD
- **Architecture:**
  - Server: 1 replica (stateful)
  - Agents: 3 replicas (auto-scaling)
- **Features:**
  - Docker-in-Docker builds
  - Auto-scaling build agents
  - Pipeline as code (`.woodpecker.yml`)
  - Integration with Gitea webhooks

#### Pipeline Flow
```
1. Developer pushes to Gitea
2. Webhook triggers Woodpecker pipeline
3. Pipeline steps:
   a. Install dependencies
   b. Lint code
   c. Run tests
   d. Build Docker image
   e. Scan image with Trivy
   f. Push to Harbor registry
   g. Update GitOps manifest repository
4. ArgoCD detects manifest change
5. ArgoCD performs rolling update
6. Health checks verify deployment
7. Slack notification sent
```

### Container Registry (Harbor)
- **Purpose:** Private Docker registry with security scanning
- **Features:**
  - Trivy vulnerability scanning
  - Retention policies (keep last 10 tags)
  - Image signing (Notary)
  - Helm chart repository
  - Replication to backup registry
- **Backend:** PostgreSQL + Redis
- **Storage:** 100Gi for images

### GitOps (ArgoCD)
- **Purpose:** Declarative continuous delivery
- **Architecture:**
  - Server: 2 replicas
  - Repo server: 2 replicas
  - Application controller: 1 replica
- **Sync Policy:**
  - Auto-sync enabled
  - Prune: true (for most apps, false for databases)
  - Self-heal: true
- **Applications Managed:**
  - glucoengine
  - mainwebsite
  - newclient
  - databases
  - monitoring

## Observability Architecture

### Metrics (Prometheus)
- **Deployment:** 2 replicas with anti-affinity
- **Storage:** 100Gi per replica (30-day retention)
- **Scrape Targets:**
  - Kubernetes API server
  - Node exporters (all nodes)
  - Application metrics (GlucoEngine `/metrics`)
  - Database exporters (MongoDB, Redis, PostgreSQL)
  - Nginx Ingress Controller
- **Long-term Storage:** Thanos sidecar (optional, for >30 days)

### Logs (Loki)
- **Deployment:** 1 StatefulSet
- **Storage:** 50Gi (30-day retention)
- **Log Collection:** Promtail DaemonSet on all nodes
- **Features:**
  - Label-based log aggregation
  - LogQL query language
  - Integration with Grafana

### Traces (Tempo)
- **Purpose:** Distributed tracing
- **Deployment:** 1 StatefulSet
- **Storage:** 30Gi
- **Protocol:** OpenTelemetry (OTLP)
- **Instrumentation:** GlucoEngine (OpenTelemetry SDK)
- **Features:**
  - Trace-to-logs correlation
  - Trace-to-metrics correlation

### Dashboards (Grafana)
- **Deployment:** 2 replicas
- **Data Sources:**
  - Prometheus (metrics)
  - Loki (logs)
  - Tempo (traces)
- **SSO:** Authentik OAuth
- **Pre-configured Dashboards:**
  1. Cluster Overview (nodes, pods, resources)
  2. GlucoEngine API Metrics (RED metrics)
  3. Database Performance (MongoDB, Redis, PostgreSQL)
  4. Business Metrics (users, readings, predictions)
  5. Infrastructure Costs

### Alerting (Alertmanager)
- **Deployment:** 2 replicas (HA)
- **Alert Routing:**
  - Critical → `#glucosync-critical` Slack channel + PagerDuty
  - Warning → `#glucosync-alerts` Slack channel
- **Alert Rules:**
  - Application down
  - High error rate (> 5%)
  - High response time (p95 > 2s)
  - Database replication lag
  - Node not ready
  - Disk space low (< 15%)
  - SSL certificate expiring (< 7 days)

## Security Architecture

### Secrets Management
- **Tool:** Sealed Secrets
- **Workflow:**
  1. Create secret locally
  2. Encrypt with `kubeseal`
  3. Commit sealed secret to Git
  4. Sealed Secrets controller decrypts in cluster
- **Secrets Stored:**
  - Database passwords
  - API keys (OpenAI, Cloudflare)
  - OAuth client secrets
  - Registry credentials

### Network Policies
- **Tool:** Calico
- **Policy Strategy:** Default deny, explicit allow
- **Rules:**
  - Apps can access their databases
  - Ingress can access all apps
  - Monitoring can scrape all metrics
  - Inter-namespace traffic restricted

### Image Scanning
- **Tool:** Trivy (integrated with Harbor)
- **Policy:** Block images with HIGH or CRITICAL vulnerabilities
- **Scan Triggers:**
  - On push to registry
  - Scheduled daily scans of existing images

### RBAC
- **User Authentication:** Authentik SSO
- **Service Accounts:** Per-application service accounts
- **Roles:**
  - `cluster-admin`: Full access (DevOps team)
  - `developer`: Read/write in `glucosync-core` namespace
  - `viewer`: Read-only cluster-wide
  - `ci-cd`: Limited access for Woodpecker/ArgoCD

### TLS/SSL
- **Certificate Management:** cert-manager
- **Issuer:** Let's Encrypt (production)
- **Challenge Type:** DNS-01 (Cloudflare)
- **Certificates:**
  - Wildcard: `*.glucosync.io`
  - Individual per service
- **Auto-renewal:** 30 days before expiry

## Backup & Disaster Recovery

### Backup Strategy

#### MongoDB Backups
- **Frequency:** Every 6 hours (CronJob)
- **Method:** `mongodump` with gzip
- **Storage:** MinIO bucket `mongodb-backups`
- **Retention:** 30 days
- **RPO:** 6 hours max data loss

#### PostgreSQL Backups
- **Method:** Continuous WAL archiving + base backups
- **Frequency:** Base backup daily, WAL continuous
- **Storage:** MinIO
- **Retention:** 7 daily, 4 weekly, 3 monthly
- **RPO:** Near-zero (PITR)

#### Volume Backups (Velero)
- **Frequency:** Daily (all namespaces), Hourly (`glucosync-data`)
- **Storage:** MinIO + off-cluster S3
- **Retention:** 7 daily, 4 weekly, 3 monthly
- **Scope:** Full cluster state

### Disaster Recovery Targets
- **RTO:** 4 hours (recovery time)
- **RPO:** 6 hours (max data loss)

### DR Procedures
1. **Database Failure:** Automatic failover via replica sets (< 30s)
2. **Node Failure:** Automatic pod rescheduling (< 5 minutes)
3. **Cluster Failure:** Rebuild cluster and restore from Velero (< 4 hours)
4. **Data Corruption:** Restore from MongoDB/PostgreSQL backups (< 2 hours)

## Scaling Strategy

### Horizontal Pod Autoscaling (HPA)
- **GlucoEngine:** 3-10 replicas (CPU > 70%)
- **Nginx Ingress:** 3-10 replicas (CPU > 70%)

### Vertical Scaling
- Increase node resources (CPU/RAM)
- Adjust resource requests/limits

### Cluster Scaling
- Add worker nodes (up to 10 with K3s)
- Migrate to full Kubernetes if > 10 nodes

### Database Scaling
- **MongoDB:** Add more replicas to replica set
- **PostgreSQL:** Add read replicas
- **Redis:** Implement Redis Cluster for sharding

## Monitoring Metrics

### Application Metrics (GlucoEngine)
```typescript
// Prometheus metrics exposed at /metrics
- glucosync_glucose_readings_total (counter)
- glucosync_ml_predictions_total (counter)
- glucosync_user_signups_total (counter)
- glucosync_api_request_duration_seconds (histogram)
- glucosync_active_websocket_connections (gauge)
- glucosync_openai_api_calls_total (counter)
```

### Infrastructure Metrics
- Node CPU/Memory/Disk usage
- Pod resource usage
- Network throughput
- PVC usage
- Certificate expiry dates

### Business Metrics
- Daily/Monthly Active Users (DAU/MAU)
- Glucose readings ingested per day
- ML predictions generated
- API usage by endpoint
- Error rate by endpoint

## Cost Optimization

### Resource Requests vs Limits
- Set requests to actual usage (not over-provision)
- Set limits 20-30% higher than requests
- Monitor actual usage in Grafana

### Storage Optimization
- Use appropriate storage classes
- Enable compression for logs
- Implement retention policies
- Delete old backups automatically

### Pod Density
- Run multiple pods per node
- Use node affinity for better bin-packing
- Right-size node instances

## Future Enhancements

### Short-term (3-6 months)
- [ ] Implement Thanos for long-term metrics storage
- [ ] Add Velero for automated disaster recovery
- [ ] Implement pod auto-scaling for all services
- [ ] Add canary deployments with Flagger

### Medium-term (6-12 months)
- [ ] Migrate to full Kubernetes (if cluster grows)
- [ ] Implement service mesh (Istio/Linkerd)
- [ ] Add multi-region deployment
- [ ] Implement blue-green deployments

### Long-term (12+ months)
- [ ] Multi-cluster federation
- [ ] Edge computing integration
- [ ] Advanced ML pipeline automation
- [ ] Cost allocation and chargeback

## Related Documentation
- [Disaster Recovery Runbook](./runbooks/disaster-recovery.md)
- [Troubleshooting Guide](./runbooks/troubleshooting.md)
- [Deployment Guide](./deployment-guide.md)
