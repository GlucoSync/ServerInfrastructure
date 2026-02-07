# GlucoSync Kubernetes Deployment Guide

## Overview

GlucoSync can be deployed in two configurations:

1. **Single-Node Cluster** (Simplest) - Everything on one server
2. **Multi-Node Cluster** (Production) - Separate control plane and workers

## Architecture Changes

**Previous Setup:**
- Separate HAProxy server
- Required at least 2 servers (1 control plane + 1+ workers + 1 HAProxy)

**Current Setup:**
- HAProxy integrated into control plane
- Can run on a single server or scale to multiple workers
- Simpler deployment and management

## Quick Start

### Single-Node Deployment (Recommended for Testing)

Perfect for development, testing, or small-scale deployments where all services run on one powerful server.

```bash
cd glucosync-k8s
nix develop  # Enter dev shell with all tools

# Deploy everything
./scripts/deploy-cluster-nix.sh
# When prompted:
# - Enter control plane IP
# - Choose "no" for workers
```

**What you get:**
- K3s Kubernetes cluster
- HAProxy load balancer (on control plane)
- All infrastructure components
- Ready to deploy applications

**Resources needed:**
- 1 server with 16GB RAM, 8+ CPU cores, 500GB SSD

### Multi-Node Deployment (Recommended for Production)

High availability setup with dedicated worker nodes for better resource isolation and scaling.

```bash
cd glucosync-k8s
nix develop

# Deploy with workers
./scripts/deploy-cluster-nix.sh
# When prompted:
# - Enter control plane IP
# - Choose "yes" for workers
# - Provide worker IPs (1-3 nodes)
```

**What you get:**
- K3s Kubernetes cluster
- HAProxy on control plane
- Workloads distributed across workers
- High availability for applications

**Resources needed:**
- Control plane: 16GB RAM, 8+ CPU cores, 500GB SSD
- Workers: 8GB RAM, 4+ CPU cores, 200GB SSD each

## Manual Deployment

### Step 1: Deploy Control Plane

```bash
export CONTROL_PLANE_IP="192.168.1.10"

nixos-rebuild switch \
    --flake .#glucosync-control-plane \
    --target-host "root@$CONTROL_PLANE_IP" \
    --build-host localhost
```

This installs:
- K3s control plane
- HAProxy load balancer
- kubectl, helm, k9s, and other tools
- Monitoring and management scripts

### Step 2: (Optional) Deploy Workers

If you want to scale beyond a single node:

```bash
# Get join token from control plane
ssh root@$CONTROL_PLANE_IP "cat /root/k3s-join-info.txt"

# Deploy each worker
export WORKER_IP="192.168.1.11"

nixos-rebuild switch \
    --flake .#glucosync-worker \
    --target-host "root@$WORKER_IP" \
    --build-host localhost
```

### Step 3: Install Components

```bash
ssh root@$CONTROL_PLANE_IP "/etc/glucosync-scripts/install-components.sh"
```

This installs:
- cert-manager (SSL certificates)
- Nginx Ingress Controller
- Longhorn storage
- Postgres Operator
- Prometheus & Grafana
- ArgoCD
- Sealed Secrets

## DNS Configuration

Point all DNS records to your **control plane IP**:

```
glucosync.io          A    <CONTROL_PLANE_IP>
*.glucosync.io        A    <CONTROL_PLANE_IP>
```

HAProxy on the control plane will route traffic to the appropriate services.

## Scaling

### Add Workers Later

You can start with a single-node cluster and add workers later:

1. Deploy new worker node(s)
2. Update HAProxy config on control plane to include new workers
3. Reload HAProxy: `systemctl reload haproxy`

### Scale Down to Single Node

If you need to reduce costs:

1. Drain and remove worker nodes
2. Update HAProxy config to only use localhost backend
3. Reload HAProxy

## Monitoring

### HAProxy Stats

View load balancer statistics:
```
http://<CONTROL_PLANE_IP>:8404/stats
```

### Cluster Status

```bash
ssh root@<CONTROL_PLANE_IP>
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes
kubectl get pods -A
```

### Using k9s

Interactive cluster management:
```bash
ssh afonso@<CONTROL_PLANE_IP>
k9s
```

## Maintenance

### Update Control Plane

```bash
nixos-rebuild switch \
    --flake .#glucosync-control-plane \
    --target-host "root@$CONTROL_PLANE_IP" \
    --build-host localhost
```

### Update Workers

```bash
for ip in 192.168.1.11 192.168.1.12; do
    nixos-rebuild switch \
        --flake .#glucosync-worker \
        --target-host "root@$ip" \
        --build-host localhost
done
```

## Troubleshooting

### Check HAProxy Status

```bash
ssh root@$CONTROL_PLANE_IP
systemctl status haproxy
journalctl -u haproxy -f
```

### Check K3s Status

```bash
ssh root@$CONTROL_PLANE_IP
systemctl status k3s
journalctl -u k3s -f
```

### Verify Cluster Connectivity

```bash
ssh root@$CONTROL_PLANE_IP
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl cluster-info
kubectl get nodes
kubectl get pods -A
```

## Migration from Old Setup

If you're migrating from the old setup with separate HAProxy:

1. Deploy new control plane with integrated HAProxy
2. Deploy workers (if desired)
3. Install components
4. Migrate data (MongoDB, etc.)
5. Update DNS to point to control plane IP
6. Decommission old HAProxy server

## Cost Optimization

### Single-Node Cluster
- **Minimum:** 1 server
- **Cost:** ~$40-80/month (Hetzner AX41 or similar)
- **Good for:** Development, testing, small deployments (<100 users)

### Multi-Node Cluster
- **Minimum:** 1 control plane + 1 worker
- **Cost:** ~$80-150/month
- **Good for:** Production, high availability (100-1000+ users)

### When to Scale

Start with single-node and add workers when:
- CPU usage consistently >70%
- Need high availability
- Want to isolate workloads
- Expecting traffic growth

## Security

### Firewall Rules

Control plane exposes:
- Port 80 (HTTP → redirects to HTTPS)
- Port 443 (HTTPS)
- Port 6443 (Kubernetes API)
- Port 8404 (HAProxy stats)

Workers don't need to expose any external ports.

### SSH Access

All nodes configured with:
- Root login via SSH key only
- Password authentication disabled
- User `afonso` with sudo access

## Next Steps

After deployment:

1. ✅ Verify cluster is running: `kubectl get nodes`
2. ✅ Configure DNS records
3. ✅ Deploy databases: `./scripts/deploy-databases.sh`
4. ✅ Deploy applications
5. ✅ Configure monitoring alerts
6. ✅ Set up backups
7. ✅ Test disaster recovery

## Support

- Documentation: See README.md
- Architecture: See docs/architecture.md
- Troubleshooting: See docs/runbooks/troubleshooting.md
