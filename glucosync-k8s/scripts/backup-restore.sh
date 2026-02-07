#!/bin/bash
set -e

# GlucoSync Backup and Restore Script

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# MongoDB backup
backup_mongodb() {
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="mongodb-backup-${TIMESTAMP}.gz"

    echo_info "Starting MongoDB backup..."

    kubectl exec mongodb-0 -n glucosync-data -- mongodump \
        --uri="mongodb://admin:${MONGO_PASSWORD}@localhost:27017/?authSource=admin" \
        --gzip \
        --archive=/tmp/${BACKUP_FILE}

    kubectl cp glucosync-data/mongodb-0:/tmp/${BACKUP_FILE} ./backups/${BACKUP_FILE}

    echo_info "MongoDB backup completed: ./backups/${BACKUP_FILE}"
}

# MongoDB restore
restore_mongodb() {
    if [[ -z "$1" ]]; then
        echo_error "Usage: $0 restore_mongodb <backup-file>"
        exit 1
    fi

    BACKUP_FILE=$1

    if [[ ! -f "$BACKUP_FILE" ]]; then
        echo_error "Backup file not found: $BACKUP_FILE"
        exit 1
    fi

    echo_warn "This will restore MongoDB from backup. Continue? (yes/no)"
    read -r response
    if [[ "$response" != "yes" ]]; then
        echo_info "Restore cancelled"
        exit 0
    fi

    echo_info "Copying backup to MongoDB pod..."
    kubectl cp $BACKUP_FILE glucosync-data/mongodb-0:/tmp/restore.gz

    echo_info "Restoring MongoDB..."
    kubectl exec mongodb-0 -n glucosync-data -- mongorestore \
        --uri="mongodb://admin:${MONGO_PASSWORD}@localhost:27017/?authSource=admin" \
        --gzip \
        --archive=/tmp/restore.gz \
        --drop

    echo_info "MongoDB restore completed"
}

# Redis backup
backup_redis() {
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="redis-backup-${TIMESTAMP}.rdb"

    echo_info "Starting Redis backup..."

    kubectl exec redis-0 -n glucosync-data -- redis-cli BGSAVE
    sleep 5

    kubectl cp glucosync-data/redis-0:/data/dump.rdb ./backups/${BACKUP_FILE}

    echo_info "Redis backup completed: ./backups/${BACKUP_FILE}"
}

# Velero backup
velero_backup() {
    BACKUP_NAME="glucosync-backup-$(date +%Y%m%d-%H%M%S)"

    echo_info "Creating Velero backup: ${BACKUP_NAME}..."

    velero backup create $BACKUP_NAME \
        --include-namespaces glucosync-core,glucosync-data,glucosync-services \
        --wait

    echo_info "Velero backup completed: ${BACKUP_NAME}"
    echo_info "List backups: velero backup get"
}

# Velero restore
velero_restore() {
    if [[ -z "$1" ]]; then
        echo_error "Usage: $0 velero_restore <backup-name>"
        exit 1
    fi

    BACKUP_NAME=$1

    echo_warn "This will restore from Velero backup. Continue? (yes/no)"
    read -r response
    if [[ "$response" != "yes" ]]; then
        echo_info "Restore cancelled"
        exit 0
    fi

    echo_info "Creating Velero restore from: ${BACKUP_NAME}..."

    velero restore create --from-backup $BACKUP_NAME --wait

    echo_info "Velero restore completed"
}

# Show menu
show_menu() {
    echo ""
    echo "GlucoSync Backup & Restore"
    echo "=========================="
    echo "1. Backup MongoDB"
    echo "2. Restore MongoDB"
    echo "3. Backup Redis"
    echo "4. Create Velero Backup (Full Cluster)"
    echo "5. Restore from Velero Backup"
    echo "0. Exit"
    echo ""
}

# Create backups directory
mkdir -p ./backups

# Main loop
while true; do
    show_menu
    read -p "Enter your choice: " choice
    case $choice in
        1) backup_mongodb ;;
        2) read -p "Enter backup file path: " file; restore_mongodb $file ;;
        3) backup_redis ;;
        4) velero_backup ;;
        5) read -p "Enter backup name: " name; velero_restore $name ;;
        0) echo_info "Exiting..."; exit 0 ;;
        *) echo_error "Invalid choice" ;;
    esac
done
