# GlucoSync Troubleshooting Guide

## Common Issues and Solutions

### Application Issues

#### Issue: GlucoEngine pods crash looping

**Symptoms:**
```bash
$ kubectl get pods -n glucosync-core
NAME                           READY   STATUS             RESTARTS   AGE
glucoengine-7d8f9c5b4d-abc12   0/1     CrashLoopBackOff   5          10m
```

**Diagnosis:**
```bash
# Check pod logs
kubectl logs -n glucosync-core glucoengine-7d8f9c5b4d-abc12

# Check previous container logs (if restarted)
kubectl logs -n glucosync-core glucoengine-7d8f9c5b4d-abc12 --previous

# Describe pod for events
kubectl describe pod -n glucosync-core glucoengine-7d8f9c5b4d-abc12
```

**Common Causes:**
1. **Database connection failure**
   ```bash
   # Test MongoDB connection from pod
   kubectl exec -it glucoengine-7d8f9c5b4d-abc12 -n glucosync-core -- \
     nc -zv mongodb-client.glucosync-data.svc.cluster.local 27017
   ```

2. **Missing secrets/config**
   ```bash
   # Verify secrets exist
   kubectl get secrets -n glucosync-core | grep glucoengine

   # Check secret contents (base64 decoded)
   kubectl get secret glucoengine-secrets -n glucosync-core -o json | \
     jq '.data | map_values(@base64d)'
   ```

3. **Out of memory**
   ```bash
   # Check resource limits
   kubectl get pod glucoengine-7d8f9c5b4d-abc12 -n glucosync-core -o json | \
     jq '.spec.containers[].resources'

   # Increase memory if needed
   kubectl set resources deployment glucoengine -n glucosync-core \
     --limits=memory=2Gi --requests=memory=1Gi
   ```

**Solution:** Fix root cause and restart deployment
```bash
kubectl rollout restart deployment glucoengine -n glucosync-core
```

---

#### Issue: High API response times

**Symptoms:**
- Grafana shows p95 latency > 2 seconds
- Users reporting slow application

**Diagnosis:**
```bash
# Check GlucoEngine metrics
kubectl port-forward -n glucosync-core svc/glucoengine 3000:80
curl http://localhost:3000/metrics | grep http_request_duration

# Check database performance
kubectl exec -it mongodb-0 -n glucosync-data -- \
  mongo admin -u admin -p PASSWORD --eval "db.currentOp()"

# Check Redis latency
kubectl exec -it redis-0 -n glucosync-data -- \
  redis-cli --latency-history
```

**Common Causes:**
1. **Database slow queries**
   - Check MongoDB slow query log
   - Add indexes if needed

2. **Redis cache misses**
   - Check cache hit ratio in Grafana
   - Verify Redis memory not full

3. **High pod CPU**
   - Check CPU metrics in Grafana
   - Scale up replicas or increase CPU limits

**Solution:**
```bash
# Scale up replicas
kubectl scale deployment glucoengine -n glucosync-core --replicas=5

# Or let HPA do it automatically (if CPU > 70%)
kubectl get hpa -n glucosync-core
```

---

### Database Issues

#### Issue: MongoDB replica set not syncing

**Symptoms:**
```bash
$ kubectl exec -it mongodb-1 -n glucosync-data -- \
    mongo --eval "rs.status()" | grep -A 5 "stateStr"
"stateStr" : "RECOVERING"
```

**Diagnosis:**
```bash
# Check replication lag
kubectl exec -it mongodb-0 -n glucosync-data -- \
  mongo admin -u admin -p PASSWORD --eval "rs.printSlaveReplicationInfo()"

# Check oplog size
kubectl exec -it mongodb-0 -n glucosync-data -- \
  mongo admin -u admin -p PASSWORD --eval "db.getReplicationInfo()"
```

**Solution:**
```bash
# If lag is too high, resync the replica
kubectl exec -it mongodb-1 -n glucosync-data -- mongo
> use admin
> db.auth("admin", "PASSWORD")
> rs.syncFrom("mongodb-0.mongodb.glucosync-data.svc.cluster.local:27017")

# If completely stuck, remove and re-add
> rs.remove("mongodb-1.mongodb.glucosync-data.svc.cluster.local:27017")
# Delete pod and let it recreate
kubectl delete pod mongodb-1 -n glucosync-data
# After pod is ready, add back
> rs.add("mongodb-1.mongodb.glucosync-data.svc.cluster.local:27017")
```

---

#### Issue: Redis out of memory

**Symptoms:**
```bash
$ kubectl logs -n glucosync-data redis-0 | grep OOM
OOM command not allowed when used memory > 'maxmemory'
```

**Diagnosis:**
```bash
# Check memory usage
kubectl exec -it redis-0 -n glucosync-data -- \
  redis-cli INFO memory

# Check eviction stats
kubectl exec -it redis-0 -n glucosync-data -- \
  redis-cli INFO stats | grep evicted
```

**Solution:**
```bash
# Option 1: Increase maxmemory
kubectl edit statefulset redis -n glucosync-data
# Update MAXMEMORY environment variable

# Option 2: Flush unused keys
kubectl exec -it redis-0 -n glucosync-data -- redis-cli
> FLUSHDB

# Option 3: Scale up Redis (add more replicas and shard)
```

---

### Networking Issues

#### Issue: Ingress not routing traffic

**Symptoms:**
- 502 Bad Gateway errors
- Services not accessible externally

**Diagnosis:**
```bash
# Check Ingress status
kubectl get ingress -A

# Check Nginx Ingress Controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

# Test from within cluster
kubectl run curl-test --image=curlimages/curl -i --tty --rm -- \
  curl http://glucoengine.glucosync-core.svc.cluster.local

# Check endpoints
kubectl get endpoints -A | grep glucoengine
```

**Common Causes:**
1. **Backend pods not ready**
   ```bash
   kubectl get pods -n glucosync-core -l app=glucoengine
   ```

2. **Certificate issues**
   ```bash
   kubectl get certificate -A
   kubectl describe certificate glucoengine-tls -n glucosync-core
   ```

3. **HAProxy misconfigured**
   ```bash
   # Check HAProxy stats
   curl http://<HAPROXY_IP>:8404/stats
   ```

**Solution:**
```bash
# Restart Ingress Controller
kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx

# Force certificate renewal
kubectl delete certificate glucoengine-tls -n glucosync-core
# Will automatically recreate

# Check HAProxy backend health
# Update haproxy.cfg if needed
```

---

#### Issue: Certificate not renewing

**Symptoms:**
- Browser shows "Certificate Expired"
- cert-manager logs show errors

**Diagnosis:**
```bash
# Check certificate status
kubectl get certificate -A
kubectl describe certificate glucoengine-tls -n glucosync-core

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Check challenges
kubectl get challenges -A
kubectl describe challenge <CHALLENGE_NAME> -n glucosync-core
```

**Solution:**
```bash
# Delete and recreate certificate
kubectl delete certificate glucoengine-tls -n glucosync-core

# Check Cloudflare API token is valid
kubectl get secret cloudflare-api-token -o jsonpath='{.data.api-token}' | base64 -d

# Manually trigger certificate request
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: glucoengine-tls
  namespace: glucosync-core
spec:
  secretName: glucoengine-tls
  issuerRef:
    name: letsencrypt-production
    kind: ClusterIssuer
  dnsNames:
    - api.glucosync.io
EOF
```

---

### Storage Issues

#### Issue: PVC stuck in Pending

**Symptoms:**
```bash
$ kubectl get pvc -A
NAMESPACE        NAME                STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
glucosync-data   mongodb-data-0      Pending                                      longhorn
```

**Diagnosis:**
```bash
# Describe PVC
kubectl describe pvc mongodb-data-0 -n glucosync-data

# Check Longhorn status
kubectl get pods -n longhorn-system

# Check available storage
kubectl get nodes -o json | \
  jq '.items[] | {name:.metadata.name, allocatable:.status.allocatable.storage}'
```

**Solution:**
```bash
# Check Longhorn UI for errors
# https://longhorn.glucosync.io

# If no storage available, add more nodes or increase disk size

# If Longhorn stuck, restart components
kubectl rollout restart deployment longhorn-driver-deployer -n longhorn-system
kubectl rollout restart daemonset longhorn-manager -n longhorn-system
```

---

### CI/CD Issues

#### Issue: Woodpecker pipeline failing

**Symptoms:**
- Build fails with error
- Deployments not updating

**Diagnosis:**
```bash
# Check Woodpecker server logs
kubectl logs -n glucosync-cicd -l app=woodpecker-server

# Check agent logs
kubectl logs -n glucosync-cicd -l app=woodpecker-agent

# Check if Docker-in-Docker working
kubectl exec -it -n glucosync-cicd <AGENT_POD> -- docker ps
```

**Solution:**
```bash
# Restart Woodpecker components
kubectl rollout restart deployment woodpecker-server -n glucosync-cicd
kubectl rollout restart deployment woodpecker-agent -n glucosync-cicd

# Check secrets are configured
kubectl get secret woodpecker-secrets -n glucosync-cicd
```

---

#### Issue: ArgoCD not syncing

**Symptoms:**
- Application shows "OutOfSync"
- Changes in Git not reflected in cluster

**Diagnosis:**
```bash
# Check ArgoCD application status
kubectl get applications -n argocd

# Describe application
kubectl describe application glucoengine -n argocd

# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

**Solution:**
```bash
# Manual sync
argocd app sync glucoengine

# Or via kubectl
kubectl patch application glucoengine -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'

# Hard refresh (ignore cache)
argocd app get glucoengine --hard-refresh
```

---

## Performance Optimization

### Optimize GlucoEngine

```bash
# Increase replicas
kubectl scale deployment glucoengine -n glucosync-core --replicas=5

# Optimize database connections
# Update ConfigMap with connection pooling settings

# Enable Redis caching
# Verify REDIS_HOST is set correctly
```

### Optimize MongoDB

```bash
# Add indexes
kubectl exec -it mongodb-0 -n glucosync-data -- mongo
> use glucosync
> db.users.createIndex({ "email": 1 })
> db.glucoseReadings.createIndex({ "userId": 1, "timestamp": -1 })

# Check query performance
> db.glucoseReadings.explain("executionStats").find({ userId: "123" })
```

### Optimize Longhorn

```bash
# Increase replica count for better IOPS
# In Longhorn UI, set replica count to 2 instead of 3 for non-critical volumes

# Enable data locality for better performance
# Settings -> General -> Data Locality = best-effort
```

---

## Useful Commands

### Quick Health Check
```bash
#!/bin/bash
echo "=== Nodes ==="
kubectl get nodes

echo "=== Pods (All Namespaces) ==="
kubectl get pods -A | grep -v Running | grep -v Completed

echo "=== Ingress Status ==="
kubectl get ingress -A

echo "=== Certificate Status ==="
kubectl get certificate -A

echo "=== PVC Status ==="
kubectl get pvc -A | grep -v Bound

echo "=== Recent Events ==="
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
```

### Port Forward Services
```bash
# Grafana
kubectl port-forward -n glucosync-monitoring svc/grafana 3000:3000

# Prometheus
kubectl port-forward -n glucosync-monitoring svc/prometheus 9090:9090

# ArgoCD
kubectl port-forward -n argocd svc/argocd-server 8080:443

# MongoDB
kubectl port-forward -n glucosync-data svc/mongodb-client 27017:27017
```

### Get Shell in Pods
```bash
# GlucoEngine
kubectl exec -it -n glucosync-core <POD_NAME> -- /bin/sh

# MongoDB
kubectl exec -it -n glucosync-data mongodb-0 -- bash

# Redis
kubectl exec -it -n glucosync-data redis-0 -- sh
```

---

## Escalation Path

| Severity | Response Time | Escalate To |
|----------|--------------|-------------|
| Critical (P0) | Immediate | On-call engineer → Manager → CTO |
| High (P1) | 30 minutes | On-call engineer → Team lead |
| Medium (P2) | 4 hours | Ticket system → Team |
| Low (P3) | 24 hours | Ticket system |

## Related Documentation
- [Disaster Recovery Runbook](./disaster-recovery.md)
- [Architecture Documentation](../architecture.md)
- [Monitoring Guide](./monitoring.md)
