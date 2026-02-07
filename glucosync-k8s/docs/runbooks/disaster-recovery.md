# GlucoSync Disaster Recovery Runbook

## Overview
This runbook provides step-by-step procedures for recovering from various disaster scenarios in the GlucoSync Kubernetes infrastructure.

**RTO (Recovery Time Objective):** 4 hours
**RPO (Recovery Point Objective):** 6 hours max data loss

## Pre-Disaster Preparation

### Verify Backups
```bash
# Check Velero backups
velero backup get

# Check MongoDB backups in MinIO
mc ls minio/mongodb-backups/

# Check PostgreSQL WAL archiving
kubectl exec -it authentik-postgres-0 -n glucosync-data -- \
  psql -U postgres -c "SELECT * FROM pg_stat_archiver;"
```

### Emergency Contact List
- **On-Call Engineer:** [Phone/Slack]
- **Backup Engineer:** [Phone/Slack]
- **Management:** [Phone/Email]
- **Cloud Provider Support:** [Phone/Ticket System]

## Disaster Scenarios

### Scenario 1: Complete Cluster Failure

**Symptoms:** All nodes unresponsive, API server down

**Recovery Steps:**

1. **Assess the Situation**
   ```bash
   # Check node status from external machine
   ssh control-plane "kubectl get nodes"

   # If SSH fails, access cloud provider console
   ```

2. **Provision New Cluster**
   ```bash
   # Run cluster setup script on new control plane
   cd glucosync-k8s/scripts
   sudo ./cluster-setup.sh
   # Select option 9 (Full Setup)
   ```

3. **Join Worker Nodes**
   ```bash
   # On each worker node
   export K3S_URL="https://<NEW_CONTROL_PLANE_IP>:6443"
   export K3S_TOKEN="<TOKEN_FROM_CONTROL_PLANE>"
   sudo ./cluster-setup.sh
   # Select option 2 (Install Worker)
   ```

4. **Install Velero**
   ```bash
   velero install \
     --provider aws \
     --bucket glucosync-backups \
     --backup-location-config \
       region=minio,s3ForcePathStyle="true",s3Url=http://minio.example.com \
     --use-volume-snapshots=false
   ```

5. **Restore from Velero Backup**
   ```bash
   # List available backups
   velero backup get

   # Restore latest backup
   velero restore create --from-backup <LATEST_BACKUP_NAME>

   # Monitor restore progress
   velero restore describe <RESTORE_NAME>
   ```

6. **Verify Services**
   ```bash
   # Check all pods are running
   kubectl get pods --all-namespaces

   # Test API endpoint
   curl https://api.glucosync.io/health

   # Test frontend
   curl https://app.glucosync.io/
   ```

**Estimated Recovery Time:** 2-3 hours

---

### Scenario 2: Database Primary Failure

#### MongoDB Primary Failure

**Symptoms:** MongoDB primary pod down, replica set not electing new primary

**Recovery Steps:**

1. **Check Replica Set Status**
   ```bash
   kubectl exec -it mongodb-0 -n glucosync-data -- \
     mongo --eval "rs.status()"
   ```

2. **Force Election (if needed)**
   ```bash
   # Connect to a secondary
   kubectl exec -it mongodb-1 -n glucosync-data -- mongo

   # Force election
   rs.stepDown()
   ```

3. **If Replica Set Stuck, Reconfigure**
   ```bash
   # Remove failed member
   rs.remove("mongodb-0.mongodb.glucosync-data.svc.cluster.local:27017")

   # Delete failed pod
   kubectl delete pod mongodb-0 -n glucosync-data

   # Wait for pod to recreate and add back to replica set
   kubectl exec -it mongodb-1 -n glucosync-data -- mongo
   rs.add("mongodb-0.mongodb.glucosync-data.svc.cluster.local:27017")
   ```

**Estimated Recovery Time:** 15-30 minutes

#### PostgreSQL Primary Failure

**Symptoms:** Authentik/Gitea/MLflow unable to connect to database

**Recovery Steps:**

1. **Check Patroni Status**
   ```bash
   kubectl exec -it authentik-postgres-0 -n glucosync-data -- \
     patronictl list
   ```

2. **Manual Failover (if needed)**
   ```bash
   kubectl exec -it authentik-postgres-0 -n glucosync-data -- \
     patronictl failover glucosync --candidate authentik-postgres-1
   ```

3. **Verify New Primary**
   ```bash
   kubectl exec -it authentik-postgres-1 -n glucosync-data -- \
     psql -U postgres -c "SELECT pg_is_in_recovery();"
   # Should return 'f' (false) for primary
   ```

**Estimated Recovery Time:** 5-10 minutes

---

### Scenario 3: Data Corruption - Restore from Backup

**Symptoms:** Incorrect data in database, user reports of data loss

**Recovery Steps:**

1. **STOP ALL WRITES IMMEDIATELY**
   ```bash
   # Scale down applications
   kubectl scale deployment glucoengine -n glucosync-core --replicas=0
   kubectl scale deployment mainwebsite -n glucosync-core --replicas=0
   kubectl scale deployment newclient -n glucosync-core --replicas=0
   ```

2. **Identify Last Good Backup**
   ```bash
   # List MongoDB backups
   mc ls minio/mongodb-backups/ | tail -20

   # Choose backup BEFORE corruption occurred
   ```

3. **Restore MongoDB**
   ```bash
   # Download backup from MinIO
   mc cp minio/mongodb-backups/mongodb-backup-TIMESTAMP.gz ./

   # Copy to MongoDB pod
   kubectl cp ./mongodb-backup-TIMESTAMP.gz glucosync-data/mongodb-0:/tmp/

   # Restore (THIS WILL DROP CURRENT DATA!)
   kubectl exec -it mongodb-0 -n glucosync-data -- \
     mongorestore --uri="mongodb://admin:PASSWORD@localhost:27017/?authSource=admin" \
     --gzip --archive=/tmp/mongodb-backup-TIMESTAMP.gz --drop
   ```

4. **Restore PostgreSQL (if needed)**
   ```bash
   # Restore from base backup + WAL
   kubectl exec -it authentik-postgres-0 -n glucosync-data -- \
     bash -c "patronictl reinit glucosync authentik-postgres-0"
   ```

5. **Verify Data Integrity**
   ```bash
   # Check record counts
   kubectl exec -it mongodb-0 -n glucosync-data -- \
     mongo admin -u admin -p PASSWORD --eval "db.users.count()"

   # Spot check critical data
   ```

6. **Resume Operations**
   ```bash
   # Scale up applications
   kubectl scale deployment glucoengine -n glucosync-core --replicas=3
   kubectl scale deployment mainwebsite -n glucosync-core --replicas=2
   kubectl scale deployment newclient -n glucosync-core --replicas=2
   ```

**Estimated Recovery Time:** 1-2 hours (depending on database size)

---

### Scenario 4: Single Node Failure

**Symptoms:** One worker node unresponsive, pods rescheduling

**Recovery Steps:**

1. **Verify Node Status**
   ```bash
   kubectl get nodes
   kubectl describe node <FAILED_NODE>
   ```

2. **Drain Node (if partially responsive)**
   ```bash
   kubectl drain <FAILED_NODE> --ignore-daemonsets --delete-emptydir-data
   ```

3. **Check Pod Rescheduling**
   ```bash
   kubectl get pods --all-namespaces -o wide | grep <FAILED_NODE>
   ```

4. **Provision Replacement Node**
   ```bash
   # SSH to new node
   export K3S_URL="https://<CONTROL_PLANE_IP>:6443"
   export K3S_TOKEN="<TOKEN>"
   curl -sfL https://get.k3s.io | K3S_URL=$K3S_URL K3S_TOKEN=$K3S_TOKEN sh -
   ```

5. **Remove Old Node**
   ```bash
   kubectl delete node <FAILED_NODE>
   ```

6. **Verify Cluster Health**
   ```bash
   kubectl get nodes
   kubectl get pods --all-namespaces
   ```

**Estimated Recovery Time:** 30-60 minutes

---

### Scenario 5: Storage Failure (Longhorn)

**Symptoms:** PVCs in pending state, pods unable to mount volumes

**Recovery Steps:**

1. **Check Longhorn Status**
   ```bash
   kubectl get pods -n longhorn-system

   # Access Longhorn UI
   # https://longhorn.glucosync.io
   ```

2. **Identify Failed Replicas**
   ```bash
   # In Longhorn UI, check volume status
   # Look for volumes with degraded replicas
   ```

3. **Recover from Replicas**
   ```bash
   # Longhorn automatically recovers if 2/3 replicas are healthy
   # If manual intervention needed, use Longhorn UI to:
   # 1. Detach volume
   # 2. Delete failed replica
   # 3. Reattach volume (new replica will be created)
   ```

4. **Restore from Backup (worst case)**
   ```bash
   # In Longhorn UI:
   # 1. Navigate to Backups
   # 2. Find latest backup for affected volume
   # 3. Click Restore
   # 4. Specify target volume name
   ```

**Estimated Recovery Time:** 1-3 hours (depending on volume size)

---

## Post-Recovery Procedures

### 1. Verify All Services
```bash
# Run health checks
./scripts/health-check.sh

# Check application logs
kubectl logs -n glucosync-core -l app=glucoengine --tail=100

# Monitor metrics
# https://grafana.glucosync.io
```

### 2. Update Monitoring
```bash
# Clear old alerts
# Check Prometheus targets are green
# Verify Grafana dashboards showing current data
```

### 3. Communication
- Notify stakeholders of recovery completion
- Document timeline of events
- Schedule post-mortem meeting

### 4. Incident Report
Create incident report including:
- Time of incident discovery
- Time of recovery completion
- Root cause analysis
- Action items to prevent recurrence
- RTO/RPO achieved vs targets

## Testing Disaster Recovery

**Schedule:** Quarterly DR drills

### DR Drill Procedure
1. Schedule drill during maintenance window
2. Announce drill to team (no user impact)
3. Simulate failure scenario
4. Execute recovery procedure
5. Time the recovery
6. Document lessons learned
7. Update runbooks if needed

### Test Checklist
- [ ] Velero backup/restore tested
- [ ] MongoDB backup/restore tested
- [ ] PostgreSQL failover tested
- [ ] Node failure recovery tested
- [ ] Complete cluster rebuild tested
- [ ] All procedures documented
- [ ] Team trained on procedures

## Emergency Contacts

| Role | Name | Phone | Email | Slack |
|------|------|-------|-------|-------|
| Primary On-Call | TBD | TBD | TBD | TBD |
| Secondary On-Call | TBD | TBD | TBD | TBD |
| Database Admin | TBD | TBD | TBD | TBD |
| Security Lead | TBD | TBD | TBD | TBD |
| Management | TBD | TBD | TBD | TBD |

## Related Documentation
- [Troubleshooting Guide](./troubleshooting.md)
- [Architecture Documentation](../architecture.md)
- [Backup Procedures](./backup-procedures.md)
