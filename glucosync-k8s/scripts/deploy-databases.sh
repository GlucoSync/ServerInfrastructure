#!/bin/bash
set -e

# GlucoSync Database Deployment Script

GREEN='\033[0;32m'
NC='\033[0m'

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_info "Deploying databases..."

# Deploy MinIO
echo_info "Deploying MinIO..."
kubectl apply -f ../k8s/base/storage/minio/statefulset.yaml

# Wait for MinIO to be ready
echo_info "Waiting for MinIO to be ready..."
kubectl wait --for=condition=ready pod -l app=minio -n glucosync-data --timeout=300s

# Deploy MongoDB
echo_info "Deploying MongoDB..."
kubectl apply -f ../k8s/base/databases/mongodb/statefulset.yaml

# Wait for MongoDB pods to be ready
echo_info "Waiting for MongoDB to be ready..."
kubectl wait --for=condition=ready pod -l app=mongodb -n glucosync-data --timeout=600s

# Initialize MongoDB replica set
echo_info "Initializing MongoDB replica set..."
kubectl exec -it mongodb-0 -n glucosync-data -- bash /etc/mongo/init-replica-set.sh

# Deploy MongoDB backup cronjob
echo_info "Deploying MongoDB backup cronjob..."
kubectl apply -f ../k8s/base/databases/mongodb/backup-cronjob.yaml

# Deploy Redis
echo_info "Deploying Redis..."
kubectl apply -f ../k8s/base/databases/redis/statefulset.yaml

# Wait for Redis to be ready
echo_info "Waiting for Redis to be ready..."
kubectl wait --for=condition=ready pod -l app=redis -n glucosync-data --timeout=600s

# Deploy PostgreSQL clusters
echo_info "Deploying PostgreSQL clusters..."
kubectl apply -f ../k8s/base/databases/postgresql/postgresql-cluster.yaml

# Wait for PostgreSQL to be ready
echo_info "Waiting for PostgreSQL to be ready..."
sleep 30
kubectl wait --for=condition=ready pod -l application=spilo -n glucosync-data --timeout=600s

echo_info "All databases deployed successfully!"
echo_info "Verify with: kubectl get pods -n glucosync-data"
