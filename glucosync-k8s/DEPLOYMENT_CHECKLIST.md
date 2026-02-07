# GlucoSync Kubernetes Deployment Checklist

Use this checklist to track progress through the 9-week migration plan.

## Week 1-2: Infrastructure Setup & Networking

### Phase 1: Infrastructure Setup (Week 1)

- [ ] **Server Provisioning**
  - [ ] Provision 1 control plane server (8 CPU, 16GB RAM, 500GB SSD)
  - [ ] Provision 2-3 worker servers (8 CPU, 16GB RAM, 500GB SSD each)
  - [ ] Install Ubuntu 22.04 LTS or Debian 12 on all servers
  - [ ] Configure SSH access to all servers
  - [ ] Set up firewall rules (ports 6443, 10250, 30080, 30443)

- [ ] **K3s Installation**
  - [ ] Run `cluster-setup.sh` on control plane (option 9: Full Setup)
  - [ ] Save K3S_TOKEN and K3S_URL from output
  - [ ] Join worker nodes using `cluster-setup.sh` (option 2)
  - [ ] Verify all nodes are Ready: `kubectl get nodes`

- [ ] **Storage Setup**
  - [ ] Verify Longhorn installed: `kubectl get pods -n longhorn-system`
  - [ ] Access Longhorn UI: `https://longhorn.glucosync.io`
  - [ ] Deploy MinIO: `kubectl apply -f k8s/base/storage/minio/`
  - [ ] Verify MinIO pods running: `kubectl get pods -n glucosync-data -l app=minio`
  - [ ] Create MinIO buckets: mongodb-backups, mlflow-artifacts, longhorn-backups

- [ ] **HAProxy Setup**
  - [ ] Provision separate VM/server for HAProxy
  - [ ] Install HAProxy: `apt-get install haproxy`
  - [ ] Copy `infrastructure/haproxy/haproxy.cfg` to `/etc/haproxy/`
  - [ ] Update worker node IPs in haproxy.cfg
  - [ ] Restart HAProxy: `systemctl restart haproxy`
  - [ ] Verify stats page: `http://<HAPROXY_IP>:8404/stats`

### Phase 2: Networking & SSL (Week 1-2)

- [ ] **Cert-Manager**
  - [ ] Verify cert-manager installed: `kubectl get pods -n cert-manager`
  - [ ] Create Cloudflare API token in Cloudflare dashboard
  - [ ] Create secret: `kubectl create secret generic cloudflare-api-token --from-literal=api-token=XXX`
  - [ ] Apply cluster issuers: `kubectl apply -f k8s/base/networking/cert-manager/cluster-issuer.yaml`

- [ ] **Nginx Ingress**
  - [ ] Verify Nginx Ingress installed: `kubectl get pods -n ingress-nginx`
  - [ ] Check NodePort services: `kubectl get svc -n ingress-nginx`
  - [ ] Test health endpoint: `curl http://<WORKER_IP>:30080/healthz`

- [ ] **DNS Configuration**
  - [ ] Create A records in Cloudflare pointing to HAProxy IP
  - [ ] Create wildcard record: `*.glucosync.io`
  - [ ] Verify DNS propagation: `dig api.glucosync.io`

- [ ] **SSL Testing**
  - [ ] Deploy test application with Ingress
  - [ ] Verify certificate issued: `kubectl get certificate -A`
  - [ ] Test HTTPS: `curl https://test.glucosync.io`
  - [ ] Switch to production issuer if staging works

---

## Week 2-3: Database Migration

### Phase 3: Database Deployment (Week 2)

- [ ] **MongoDB Replica Set**
  - [ ] Create MongoDB credentials secret
  - [ ] Deploy MongoDB: `kubectl apply -f k8s/base/databases/mongodb/statefulset.yaml`
  - [ ] Wait for all 3 pods ready: `kubectl get pods -n glucosync-data -l app=mongodb`
  - [ ] Initialize replica set: `kubectl exec -it mongodb-0 -n glucosync-data -- bash /etc/mongo/init-replica-set.sh`
  - [ ] Verify replica set: `rs.status()`
  - [ ] Import data from Docker Compose MongoDB
  - [ ] Deploy backup CronJob: `kubectl apply -f k8s/base/databases/mongodb/backup-cronjob.yaml`
  - [ ] Test failover: Delete primary pod and verify new election

- [ ] **Redis Sentinel**
  - [ ] Create Redis credentials secret
  - [ ] Deploy Redis: `kubectl apply -f k8s/base/databases/redis/statefulset.yaml`
  - [ ] Verify Redis pods: `kubectl get pods -n glucosync-data -l app=redis`
  - [ ] Verify Sentinel pods: `kubectl get pods -n glucosync-data -l app=redis-sentinel`
  - [ ] Test failover: `kubectl delete pod redis-0 -n glucosync-data`
  - [ ] Verify automatic promotion

- [ ] **PostgreSQL Clusters**
  - [ ] Install Zalando Postgres Operator
  - [ ] Deploy PostgreSQL clusters: `kubectl apply -f k8s/base/databases/postgresql/postgresql-cluster.yaml`
  - [ ] Verify clusters ready: `kubectl get postgresql -n glucosync-data`
  - [ ] Test connectivity to each cluster
  - [ ] Test failover: Delete primary pod

---

## Week 3-4: Services & Applications

### Phase 4: Core Services (Week 3)

- [ ] **Authentik (SSO)**
  - [ ] Create Authentik secrets
  - [ ] Deploy Authentik: `kubectl apply -f k8s/base/services/authentik/deployment.yaml`
  - [ ] Access Authentik UI: `https://auth.glucosync.io`
  - [ ] Complete initial setup wizard
  - [ ] Create admin user
  - [ ] Create OAuth applications for: Grafana, ArgoCD, Gitea, Harbor

- [ ] **MLflow**
  - [ ] Deploy MLflow: `kubectl apply -f k8s/base/services/mlflow/deployment.yaml`
  - [ ] Access MLflow UI: `https://mlflow.glucosync.io`
  - [ ] Test artifact upload to MinIO
  - [ ] Migrate existing experiments from Docker Compose

- [ ] **MinIO Console**
  - [ ] Create Ingress for MinIO console
  - [ ] Access console: `https://minio.glucosync.io`
  - [ ] Verify buckets exist
  - [ ] Set up lifecycle policies (30-day retention for backups)

### Phase 5: Application Deployment (Week 4)

- [ ] **GlucoEngine (Backend API)**
  - [ ] Build Docker image: `cd docker/glucoengine && docker build -t glucoengine:latest .`
  - [ ] Push to temporary registry or Harbor
  - [ ] Create secrets: glucoengine-secrets (JWT, OpenAI key, etc.)
  - [ ] Deploy: `kubectl apply -f k8s/base/applications/glucoengine/deployment.yaml`
  - [ ] Verify 3 pods running: `kubectl get pods -n glucosync-core -l app=glucoengine`
  - [ ] Check logs: `kubectl logs -n glucosync-core -l app=glucoengine`
  - [ ] Test API: `curl https://api.glucosync.io/health`
  - [ ] Verify HPA: `kubectl get hpa -n glucosync-core`
  - [ ] Test rolling update: Update image and watch rollout

- [ ] **MainWebsite (Marketing Site)**
  - [ ] Build Docker image: `cd docker/mainwebsite && docker build -t mainwebsite:latest .`
  - [ ] Deploy: `kubectl apply -f k8s/base/applications/mainwebsite/deployment.yaml`
  - [ ] Test: `curl https://glucosync.io`

- [ ] **NewClient (PWA)**
  - [ ] Build Docker image: `cd docker/newclient && docker build -t newclient:latest .`
  - [ ] Deploy: `kubectl apply -f k8s/base/applications/newclient/deployment.yaml`
  - [ ] Test: `curl https://app.glucosync.io`
  - [ ] Test PWA offline functionality
  - [ ] Test service worker registration

---

## Week 5-6: CI/CD & Monitoring

### Phase 6: CI/CD Setup (Week 5)

- [ ] **Gitea**
  - [ ] Deploy Gitea: `kubectl apply -f k8s/base/cicd/gitea/statefulset.yaml`
  - [ ] Access UI: `https://git.glucosync.io`
  - [ ] Complete setup wizard
  - [ ] Configure Authentik SSO integration
  - [ ] Create organization: glucosync
  - [ ] Create repositories: glucoengine, mainwebsite, newclient, k8s-manifests
  - [ ] Migrate code from existing Git

- [ ] **Woodpecker CI**
  - [ ] Create Woodpecker secrets (Gitea OAuth)
  - [ ] Deploy Woodpecker: `kubectl apply -f k8s/base/cicd/woodpecker/deployment.yaml`
  - [ ] Access UI: `https://ci.glucosync.io`
  - [ ] Connect to Gitea
  - [ ] Activate repositories
  - [ ] Copy `.woodpecker.yml` to each repository
  - [ ] Test pipeline: Make a commit and watch build

- [ ] **Harbor Registry**
  - [ ] Add Helm repo: `helm repo add harbor https://helm.goharbor.io`
  - [ ] Install Harbor: `helm install harbor harbor/harbor -f k8s/base/cicd/harbor/values.yaml -n glucosync-cicd`
  - [ ] Access UI: `https://harbor.glucosync.io`
  - [ ] Create admin user
  - [ ] Create project: glucosync
  - [ ] Configure Trivy scanner
  - [ ] Create robot account for CI
  - [ ] Test image push/pull

- [ ] **ArgoCD**
  - [ ] Install ArgoCD: `kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml`
  - [ ] Get admin password: `kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d`
  - [ ] Access UI: `https://argocd.glucosync.io`
  - [ ] Connect to Gitea repository
  - [ ] Create AppProject: glucosync
  - [ ] Create Applications: `kubectl apply -f k8s/base/cicd/argocd/applications.yaml`
  - [ ] Configure auto-sync
  - [ ] Test GitOps flow: Update manifest in Git and watch ArgoCD sync

- [ ] **End-to-End CI/CD Test**
  - [ ] Make code change in glucoengine
  - [ ] Push to Gitea
  - [ ] Verify Woodpecker pipeline runs
  - [ ] Verify image built and pushed to Harbor
  - [ ] Verify manifest updated in k8s-manifests repo
  - [ ] Verify ArgoCD syncs and deploys new version
  - [ ] Verify zero-downtime rolling update
  - [ ] Check Slack notification

### Phase 7: Monitoring & Observability (Week 6)

- [ ] **Prometheus**
  - [ ] Verify Prometheus Operator installed
  - [ ] Deploy Prometheus: `kubectl apply -f k8s/base/monitoring/prometheus/prometheus.yaml`
  - [ ] Apply ServiceMonitors: `kubectl apply -f k8s/base/monitoring/prometheus/servicemonitors.yaml`
  - [ ] Apply alert rules: `kubectl apply -f k8s/base/monitoring/prometheus/alerts.yaml`
  - [ ] Access UI: `https://prometheus.glucosync.io`
  - [ ] Verify all targets scraping (Status → Targets)

- [ ] **Grafana**
  - [ ] Create Grafana OAuth secret (Authentik)
  - [ ] Deploy Grafana: `kubectl apply -f k8s/base/monitoring/grafana/deployment.yaml`
  - [ ] Access UI: `https://grafana.glucosync.io`
  - [ ] Login with Authentik
  - [ ] Verify data sources configured (Prometheus, Loki, Tempo)
  - [ ] Import dashboards from `monitoring/dashboards/`
  - [ ] Create custom GlucoSync business metrics dashboard

- [ ] **Loki & Promtail**
  - [ ] Deploy Loki: `kubectl apply -f k8s/base/monitoring/loki/statefulset.yaml`
  - [ ] Verify logs ingesting: Check Grafana Explore → Loki
  - [ ] Create log-based alerts

- [ ] **Tempo**
  - [ ] Deploy Tempo: `kubectl apply -f k8s/base/monitoring/tempo/statefulset.yaml`
  - [ ] Instrument GlucoEngine with OpenTelemetry
  - [ ] Verify traces in Grafana: Explore → Tempo
  - [ ] Test trace-to-logs correlation

- [ ] **Alertmanager**
  - [ ] Create Slack webhook secret
  - [ ] Deploy Alertmanager: `kubectl apply -f k8s/base/monitoring/alertmanager/deployment.yaml`
  - [ ] Configure alert routing
  - [ ] Test alerts: Trigger test alert
  - [ ] Verify Slack notification received

---

## Week 7-8: Security & Backups

### Phase 8: Security Hardening (Week 7)

- [ ] **Sealed Secrets**
  - [ ] Install Sealed Secrets controller
  - [ ] Migrate all secrets to Sealed Secrets
  - [ ] Commit sealed secrets to Git
  - [ ] Delete plain secrets from cluster

- [ ] **Network Policies**
  - [ ] Install Calico
  - [ ] Create default deny policies
  - [ ] Create allow policies for necessary traffic
  - [ ] Test policies (verify unauthorized traffic blocked)

- [ ] **RBAC**
  - [ ] Create service accounts for each application
  - [ ] Define Roles and RoleBindings
  - [ ] Create ClusterRoles for admin access
  - [ ] Integrate with Authentik for user authentication

- [ ] **Image Scanning**
  - [ ] Verify Trivy scanning enabled in Harbor
  - [ ] Configure webhook to block vulnerable images
  - [ ] Run security audit: `kubectl run kube-bench ...`

### Phase 9: Backup & Disaster Recovery (Week 8)

- [ ] **Velero Installation**
  - [ ] Install Velero CLI
  - [ ] Install Velero server with MinIO backend
  - [ ] Configure backup schedules: Daily (all namespaces), Hourly (glucosync-data)
  - [ ] Set retention policies: 7 daily, 4 weekly, 3 monthly

- [ ] **Backup Testing**
  - [ ] Trigger manual Velero backup
  - [ ] Test MongoDB restore from backup
  - [ ] Test full namespace restore
  - [ ] Document restore time (must be < 4 hours RTO)

- [ ] **Disaster Recovery Drills**
  - [ ] Simulate node failure → Verify pod rescheduling
  - [ ] Simulate database primary failure → Verify automatic failover
  - [ ] Simulate complete cluster failure → Test full rebuild from backups
  - [ ] Update DR runbook with actual recovery times

---

## Week 9: Production Cutover

### Phase 10: Production Migration (Week 9)

- [ ] **Pre-Cutover Checklist**
  - [ ] All services deployed and healthy
  - [ ] End-to-end testing passed
  - [ ] Load testing completed (2x expected peak traffic)
  - [ ] Security audit passed
  - [ ] Backup/restore tested successfully
  - [ ] Monitoring and alerting active and verified
  - [ ] Runbooks documented and reviewed
  - [ ] Team trained on new infrastructure
  - [ ] Rollback plan documented and tested

- [ ] **Cutover Execution** (Schedule 3-hour maintenance window)
  - [ ] Announce maintenance window to users (1 week notice)
  - [ ] Set up 24/7 on-call coverage
  - [ ] Enable read-only mode on Docker Compose services
  - [ ] Perform final data sync to Kubernetes databases
  - [ ] Verify data integrity (record counts match)
  - [ ] Update DNS records to point to HAProxy
  - [ ] Monitor for 30 minutes (check Grafana, logs, error rates)
  - [ ] Run smoke tests (API health checks, user login, core features)
  - [ ] Announce completion if successful

- [ ] **Post-Cutover Monitoring** (First Week)
  - [ ] Monitor Grafana dashboards 24/7
  - [ ] Review error logs daily
  - [ ] Check database replication lag
  - [ ] Verify backups running on schedule
  - [ ] Daily team sync to address any issues
  - [ ] Keep Docker Compose infrastructure running (fallback for 1 week)

- [ ] **Post-Cutover Optimization** (First Month)
  - [ ] Analyze performance metrics vs SLAs
  - [ ] Optimize resource requests/limits based on actual usage
  - [ ] Fine-tune HPA thresholds
  - [ ] Adjust alert thresholds to reduce noise
  - [ ] Conduct post-mortem meeting
  - [ ] Update documentation based on lessons learned

- [ ] **Decommission Docker Compose** (After 1 Month)
  - [ ] Verify Kubernetes stable (no major incidents)
  - [ ] Perform final data comparison
  - [ ] Shut down Docker Compose services
  - [ ] Archive Docker Compose configs
  - [ ] Release resources

---

## Success Criteria Verification

- [ ] ✅ Zero downtime achieved during all deployments
- [ ] ✅ Database failover time < 30 seconds
- [ ] ✅ API response time p95 < 2 seconds
- [ ] ✅ Uptime > 99.9% (< 43 minutes downtime/month)
- [ ] ✅ SSL certificates auto-renewing (verify 30 days before expiry)
- [ ] ✅ All services monitored with active alerts
- [ ] ✅ Backups running and tested (successful restore)
- [ ] ✅ CI/CD pipeline < 10 minute build time
- [ ] ✅ No HIGH or CRITICAL security vulnerabilities
- [ ] ✅ All runbooks documented and tested

---

## Notes & Issues

Use this space to track issues encountered and their resolutions:

| Date | Issue | Resolution | Time Lost |
|------|-------|------------|-----------|
|      |       |            |           |
|      |       |            |           |
|      |       |            |           |
