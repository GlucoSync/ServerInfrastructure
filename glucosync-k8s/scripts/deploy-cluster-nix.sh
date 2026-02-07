#!/usr/bin/env bash
set -e

# GlucoSync Kubernetes Cluster Deployment Script (Nix-based)
# This script deploys the entire cluster using NixOS flakes

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo_step() {
    echo -e "${BLUE}==>${NC} $1"
}

# Check if nix is installed
if ! command -v nix &> /dev/null; then
    echo_error "Nix is not installed! Please install Nix first:"
    echo "  curl -L https://nixos.org/nix/install | sh"
    exit 1
fi

# Check if we're in the right directory
if [ ! -f "flake.nix" ]; then
    echo_error "flake.nix not found! Please run this from the glucosync-k8s directory"
    exit 1
fi

# Configuration
CONTROL_PLANE_IP=${CONTROL_PLANE_IP:-""}
WORKER1_IP=${WORKER1_IP:-""}
WORKER2_IP=${WORKER2_IP:-""}
WORKER3_IP=${WORKER3_IP:-""}
HAPROXY_IP=${HAPROXY_IP:-""}

# Interactive mode if IPs not provided
if [ -z "$CONTROL_PLANE_IP" ]; then
    echo_step "Enter Control Plane IP address:"
    read CONTROL_PLANE_IP
fi

if [ -z "$WORKER1_IP" ]; then
    echo_step "Enter Worker 1 IP address:"
    read WORKER1_IP
fi

if [ -z "$WORKER2_IP" ]; then
    echo_step "Enter Worker 2 IP address (leave empty to skip):"
    read WORKER2_IP
fi

if [ -z "$WORKER3_IP" ]; then
    echo_step "Enter Worker 3 IP address (leave empty to skip):"
    read WORKER3_IP
fi

if [ -z "$HAPROXY_IP" ]; then
    echo_step "Enter HAProxy IP address:"
    read HAPROXY_IP
fi

echo ""
echo_info "Cluster Configuration:"
echo "  Control Plane: $CONTROL_PLANE_IP"
echo "  Worker 1: $WORKER1_IP"
[ -n "$WORKER2_IP" ] && echo "  Worker 2: $WORKER2_IP"
[ -n "$WORKER3_IP" ] && echo "  Worker 3: $WORKER3_IP"
echo "  HAProxy: $HAPROXY_IP"
echo ""

# Confirm
echo_step "Proceed with deployment? (yes/no)"
read -r response
if [[ "$response" != "yes" ]]; then
    echo_info "Deployment cancelled"
    exit 0
fi

# Step 1: Deploy Control Plane
echo_step "Step 1: Deploying Control Plane..."
echo_info "Deploying NixOS configuration to $CONTROL_PLANE_IP"

nixos-rebuild switch \
    --flake .#glucosync-control-plane \
    --target-host "root@$CONTROL_PLANE_IP" \
    --build-host localhost

echo_info "Control plane deployed!"
echo_info "Waiting 30 seconds for K3s to initialize..."
sleep 30

# Get K3s token from control plane
echo_info "Retrieving K3s join token..."
K3S_TOKEN=$(ssh root@$CONTROL_PLANE_IP "cat /var/lib/rancher/k3s/server/node-token")
K3S_URL="https://$CONTROL_PLANE_IP:6443"

echo_info "K3S_URL: $K3S_URL"
echo_info "K3S_TOKEN: [retrieved]"

# Step 2: Deploy Workers
deploy_worker() {
    local WORKER_IP=$1
    local WORKER_NUM=$2

    echo_step "Step 2.$WORKER_NUM: Deploying Worker Node $WORKER_NUM ($WORKER_IP)..."

    # Create temporary environment file with K3s connection info
    ssh root@$WORKER_IP "mkdir -p /etc/rancher/k3s"
    ssh root@$WORKER_IP "cat > /etc/rancher/k3s/k3s.env <<EOF
K3S_URL=$K3S_URL
K3S_TOKEN=$K3S_TOKEN
EOF"

    # Update worker config with control plane IP
    TEMP_WORKER_CONFIG=$(mktemp)
    sed "s/CONTROL_PLANE_IP/$CONTROL_PLANE_IP/g" nixos/modules/k3s-agent.nix > "$TEMP_WORKER_CONFIG"
    scp "$TEMP_WORKER_CONFIG" "root@$WORKER_IP:/tmp/k3s-agent.nix"
    ssh root@$WORKER_IP "mkdir -p /etc/nixos/modules && mv /tmp/k3s-agent.nix /etc/nixos/modules/"
    rm "$TEMP_WORKER_CONFIG"

    # Deploy NixOS configuration
    nixos-rebuild switch \
        --flake .#glucosync-worker \
        --target-host "root@$WORKER_IP" \
        --build-host localhost

    echo_info "Worker $WORKER_NUM deployed!"
}

deploy_worker "$WORKER1_IP" 1
[ -n "$WORKER2_IP" ] && deploy_worker "$WORKER2_IP" 2
[ -n "$WORKER3_IP" ] && deploy_worker "$WORKER3_IP" 3

echo_info "Waiting for workers to join cluster..."
sleep 20

# Step 3: Verify cluster
echo_step "Step 3: Verifying cluster..."
ssh root@$CONTROL_PLANE_IP "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl get nodes"

# Step 4: Deploy HAProxy
echo_step "Step 4: Deploying HAProxy Load Balancer..."

# Update HAProxy config with actual IPs
TEMP_HAPROXY_CONFIG=$(mktemp)
sed -e "s/WORKER1_IP/$WORKER1_IP/g" \
    -e "s/WORKER2_IP/$WORKER2_IP/g" \
    -e "s/WORKER3_IP/$WORKER3_IP/g" \
    -e "s/CONTROLPLANE_IP/$CONTROL_PLANE_IP/g" \
    nixos/haproxy.nix > "$TEMP_HAPROXY_CONFIG"

scp "$TEMP_HAPROXY_CONFIG" "root@$HAPROXY_IP:/tmp/haproxy.nix"
ssh root@$HAPROXY_IP "mkdir -p /etc/nixos && mv /tmp/haproxy.nix /etc/nixos/"
rm "$TEMP_HAPROXY_CONFIG"

nixos-rebuild switch \
    --flake .#glucosync-haproxy \
    --target-host "root@$HAPROXY_IP" \
    --build-host localhost

echo_info "HAProxy deployed!"

# Step 5: Install Kubernetes components
echo_step "Step 5: Installing Kubernetes components..."
ssh root@$CONTROL_PLANE_IP "/etc/glucosync-scripts/install-components.sh"

# Summary
echo ""
echo_info "╔══════════════════════════════════════════════════════════════╗"
echo_info "║                                                              ║"
echo_info "║     🎉 GlucoSync Kubernetes Cluster Deployed! 🎉            ║"
echo_info "║                                                              ║"
echo_info "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo_info "Cluster Status:"
echo "  Control Plane: $CONTROL_PLANE_IP"
echo "  Workers: $(echo $WORKER1_IP $WORKER2_IP $WORKER3_IP | tr -s ' ')"
echo "  HAProxy: $HAPROXY_IP"
echo ""
echo_info "Next Steps:"
echo "  1. Configure DNS to point to $HAPROXY_IP"
echo "  2. Deploy applications: kubectl apply -f k8s/base/applications/"
echo "  3. Access Grafana: https://grafana.glucosync.io"
echo "  4. Access ArgoCD: https://argocd.glucosync.io"
echo ""
echo_info "Get ArgoCD admin password:"
echo "  ssh root@$CONTROL_PLANE_IP 'kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath=\"{.data.password}\" | base64 -d'"
echo ""
echo_info "SSH into nodes:"
echo "  ssh afonso@$CONTROL_PLANE_IP"
echo "  ssh afonso@$WORKER1_IP"
echo ""
