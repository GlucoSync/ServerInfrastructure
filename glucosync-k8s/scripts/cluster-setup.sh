#!/bin/bash
set -e

# GlucoSync Kubernetes Cluster Setup Script
# This script automates the initial setup of the K3s cluster

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo_error "This script must be run as root"
   exit 1
fi

# Function to install K3s on control plane
install_control_plane() {
    echo_info "Installing K3s control plane..."

    curl -sfL https://get.k3s.io | sh -s - server \
        --disable traefik \
        --disable servicelb \
        --write-kubeconfig-mode 644 \
        --cluster-init \
        --tls-san $(hostname -I | awk '{print $1}')

    echo_info "K3s control plane installed successfully"

    # Wait for K3s to be ready
    echo_info "Waiting for K3s to be ready..."
    sleep 10

    # Get node token for workers
    K3S_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)
    K3S_URL="https://$(hostname -I | awk '{print $1}'):6443"

    echo_info "K3s Token: ${K3S_TOKEN}"
    echo_info "K3s URL: ${K3S_URL}"
    echo_warn "Save these values to join worker nodes!"
}

# Function to install K3s on worker
install_worker() {
    if [[ -z "$K3S_URL" ]] || [[ -z "$K3S_TOKEN" ]]; then
        echo_error "K3S_URL and K3S_TOKEN environment variables must be set"
        exit 1
    fi

    echo_info "Installing K3s worker..."

    curl -sfL https://get.k3s.io | K3S_URL=$K3S_URL K3S_TOKEN=$K3S_TOKEN sh -

    echo_info "K3s worker installed successfully"
}

# Function to install Longhorn
install_longhorn() {
    echo_info "Installing Longhorn storage..."

    # Install dependencies
    apt-get update
    apt-get install -y open-iscsi nfs-common
    systemctl enable --now iscsid

    # Install Longhorn
    kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.5.3/deploy/longhorn.yaml

    echo_info "Waiting for Longhorn to be ready..."
    kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=600s

    # Apply Longhorn configuration
    kubectl apply -f ../k8s/base/storage/longhorn/values.yaml

    echo_info "Longhorn installed successfully"
}

# Function to install cert-manager
install_cert_manager() {
    echo_info "Installing cert-manager..."

    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

    echo_info "Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s

    echo_info "cert-manager installed successfully"
}

# Function to install Nginx Ingress
install_nginx_ingress() {
    echo_info "Installing Nginx Ingress Controller..."

    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update

    helm install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --create-namespace \
        -f ../k8s/base/networking/nginx-ingress/values.yaml

    echo_info "Waiting for Nginx Ingress to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx --timeout=300s

    echo_info "Nginx Ingress installed successfully"
}

# Function to create namespaces
create_namespaces() {
    echo_info "Creating namespaces..."
    kubectl apply -f ../k8s/base/namespaces/namespaces.yaml
    echo_info "Namespaces created successfully"
}

# Function to install Zalando Postgres Operator
install_postgres_operator() {
    echo_info "Installing Zalando Postgres Operator..."
    kubectl apply -k github.com/zalando/postgres-operator/manifests

    echo_info "Waiting for Postgres Operator to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgres-operator -n default --timeout=300s

    echo_info "Postgres Operator installed successfully"
}

# Function to create secrets (interactive)
create_secrets() {
    echo_info "Creating secrets..."

    # Cloudflare API token
    read -sp "Enter Cloudflare API token: " CF_TOKEN
    echo
    kubectl create secret generic cloudflare-api-token \
        --from-literal=api-token=$CF_TOKEN \
        --dry-run=client -o yaml | kubectl apply -f -

    # MongoDB credentials
    read -sp "Enter MongoDB root password: " MONGO_PASSWORD
    echo
    kubectl create secret generic mongodb-credentials \
        --namespace=glucosync-data \
        --from-literal=root-username=admin \
        --from-literal=root-password=$MONGO_PASSWORD \
        --dry-run=client -o yaml | kubectl apply -f -

    # Redis credentials
    read -sp "Enter Redis password: " REDIS_PASSWORD
    echo
    kubectl create secret generic redis-credentials \
        --namespace=glucosync-data \
        --from-literal=password=$REDIS_PASSWORD \
        --dry-run=client -o yaml | kubectl apply -f -

    # MinIO credentials
    read -sp "Enter MinIO root user: " MINIO_USER
    echo
    read -sp "Enter MinIO root password: " MINIO_PASSWORD
    echo
    kubectl create secret generic minio-credentials \
        --namespace=glucosync-data \
        --from-literal=root-user=$MINIO_USER \
        --from-literal=root-password=$MINIO_PASSWORD \
        --dry-run=client -o yaml | kubectl apply -f -

    echo_info "Secrets created successfully"
}

# Main menu
show_menu() {
    echo ""
    echo "GlucoSync Kubernetes Cluster Setup"
    echo "==================================="
    echo "1. Install K3s Control Plane"
    echo "2. Install K3s Worker Node"
    echo "3. Install Longhorn Storage"
    echo "4. Install cert-manager"
    echo "5. Install Nginx Ingress Controller"
    echo "6. Create Namespaces"
    echo "7. Install Postgres Operator"
    echo "8. Create Secrets"
    echo "9. Full Setup (Control Plane Only)"
    echo "0. Exit"
    echo ""
}

full_setup() {
    echo_info "Starting full cluster setup..."
    install_control_plane
    sleep 10
    create_namespaces
    install_longhorn
    install_cert_manager
    install_nginx_ingress
    install_postgres_operator
    create_secrets
    echo_info "Full cluster setup completed!"
    echo_warn "Next steps:"
    echo "  1. Join worker nodes using the K3S_URL and K3S_TOKEN"
    echo "  2. Apply database manifests"
    echo "  3. Deploy applications"
}

# Main loop
while true; do
    show_menu
    read -p "Enter your choice: " choice
    case $choice in
        1) install_control_plane ;;
        2) install_worker ;;
        3) install_longhorn ;;
        4) install_cert_manager ;;
        5) install_nginx_ingress ;;
        6) create_namespaces ;;
        7) install_postgres_operator ;;
        8) create_secrets ;;
        9) full_setup ;;
        0) echo_info "Exiting..."; exit 0 ;;
        *) echo_error "Invalid choice" ;;
    esac
done
