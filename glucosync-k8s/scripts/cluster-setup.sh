#!/bin/bash
set -e

# GlucoSync Kubernetes Cluster Setup Script
# This script automates the initial setup of the K3s cluster with comprehensive security hardening

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

# Detect the script directory and set absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
K8S_BASE_DIR="${PROJECT_ROOT}/k8s/base"

echo_info "Script directory: $SCRIPT_DIR"
echo_info "Project root: $PROJECT_ROOT"
echo_info "K8s base directory: $K8S_BASE_DIR"

# Function to harden system security
harden_system() {
    echo_info "Hardening system security..."

    # Update system packages
    echo_info "Updating system packages..."
    apt-get update
    apt-get upgrade -y

    # Install security packages
    echo_info "Installing security packages..."
    apt-get install -y \
        fail2ban \
        ufw \
        auditd \
        unattended-upgrades \
        apt-listchanges \
        needrestart \
        libpam-tmpdir \
        libpam-pwquality \
        apparmor \
        apparmor-utils \
        apparmor-profiles \
        rkhunter \
        aide \
        lynis

    # Configure automatic security updates
    echo_info "Configuring automatic security updates..."
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::InstallOnShutdown "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";
EOF

    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    # Configure SSH hardening
    echo_info "Hardening SSH configuration..."
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    cat > /etc/ssh/sshd_config << 'EOF'
# GlucoSync Hardened SSH Configuration
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Authentication
PermitRootLogin prohibit-password
StrictModes yes
MaxAuthTries 3
MaxSessions 10
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Security settings
X11Forwarding no
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
PermitUserEnvironment no
Compression delayed
ClientAliveInterval 300
ClientAliveCountMax 2
UseDNS no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no

# Logging
SyslogFacility AUTH
LogLevel VERBOSE

# Override default of no subsystems
Subsystem sftp /usr/lib/openssh/sftp-server -f AUTHPRIV -l INFO
EOF

    systemctl restart sshd

    # Configure fail2ban
    echo_info "Configuring fail2ban..."
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
destemail = root@localhost
sendername = Fail2Ban
banaction = iptables-multiport
banaction_allports = iptables-allports

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3
findtime = 600
bantime = 3600

[sshd-ddos]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 6
findtime = 600
bantime = 3600

[k3s-api]
enabled = true
port = 6443
logpath = /var/log/k3s.log
maxretry = 5
findtime = 300
bantime = 1800
EOF

    systemctl enable fail2ban
    systemctl restart fail2ban

    # Configure UFW firewall
    echo_info "Configuring UFW firewall..."
    ufw --force disable
    ufw --force reset
    
    # Default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH with rate limiting
    ufw limit ssh/tcp comment 'SSH with rate limiting'
    
    # Allow K3s API server (will be configured per node type)
    # ufw allow 6443/tcp comment 'K3s API server'
    
    # Enable UFW
    ufw --force enable

    # Configure kernel security parameters
    echo_info "Configuring kernel security parameters..."
    cat > /etc/sysctl.d/99-glucosync-security.conf << 'EOF'
# GlucoSync Kernel Security Configuration

# IP forwarding (required for Kubernetes)
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# TCP hardening
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_fin_timeout = 15

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Do not send ICMP redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Ignore ICMP ping requests (optional - may want to keep enabled for monitoring)
net.ipv4.icmp_echo_ignore_all = 0

# Log suspicious packets
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Ignore bogus ICMP errors
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Enable source validation
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Protect against time-wait assassination
net.ipv4.tcp_rfc1337 = 1

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Kernel hardening
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.unprivileged_bpf_disabled = 1
kernel.yama.ptrace_scope = 2

# Disable core dumps
kernel.core_uses_pid = 1
fs.suid_dumpable = 0

# Increase system file descriptor limit for Kubernetes
fs.file-max = 2097152
fs.nr_open = 2097152
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288

# Virtual memory tuning
vm.swappiness = 10
vm.dirty_ratio = 60
vm.dirty_background_ratio = 2
vm.overcommit_memory = 1
vm.panic_on_oom = 0
EOF

    sysctl -p /etc/sysctl.d/99-glucosync-security.conf

    # Configure auditd
    echo_info "Configuring audit daemon..."
    cat >> /etc/audit/rules.d/glucosync.rules << 'EOF'
# GlucoSync Audit Rules

# Monitor authentication
-w /var/log/auth.log -p wa -k auth_log
-w /etc/ssh/sshd_config -p wa -k sshd_config

# Monitor user changes
-w /etc/passwd -p wa -k passwd_changes
-w /etc/group -p wa -k group_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /etc/sudoers.d/ -p wa -k sudoers_changes

# Monitor network changes
-w /etc/network/ -p wa -k network_changes
-w /etc/netplan/ -p wa -k network_changes

# Monitor K3s
-w /etc/rancher/ -p wa -k k3s_config
-w /var/lib/rancher/ -p wa -k k3s_data

# Monitor cron jobs
-w /etc/cron.allow -p wa -k cron_changes
-w /etc/cron.deny -p wa -k cron_changes
-w /etc/crontab -p wa -k cron_changes
-w /etc/cron.d/ -p wa -k cron_changes

# Monitor kernel module loading
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules
-a always,exit -F arch=b64 -S init_module,delete_module -k modules
EOF

    systemctl enable auditd
    systemctl restart auditd

    # Set up AppArmor
    echo_info "Enabling AppArmor..."
    systemctl enable apparmor
    systemctl start apparmor

    # Configure security limits
    echo_info "Configuring security limits..."
    cat >> /etc/security/limits.conf << 'EOF'

# GlucoSync Security Limits
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
root soft nofile 65536
root hard nofile 65536
root soft nproc 32768
root hard nproc 32768
EOF

    # Disable unnecessary services
    echo_info "Disabling unnecessary services..."
    systemctl disable --now avahi-daemon.service 2>/dev/null || true
    systemctl disable --now cups.service 2>/dev/null || true
    systemctl disable --now bluetooth.service 2>/dev/null || true

    # Set up AIDE (file integrity monitoring)
    echo_info "Initializing AIDE..."
    aideinit
    mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db

    # Set up daily security scan
    echo_info "Setting up daily security scans..."
    cat > /usr/local/bin/glucosync-security-scan.sh << 'EOF'
#!/bin/bash
# GlucoSync Daily Security Scan

echo "=== GlucoSync Security Scan - $(date) ===" | tee -a /var/log/glucosync-security.log

echo "Failed SSH attempts:" | tee -a /var/log/glucosync-security.log
grep "Failed password" /var/log/auth.log 2>/dev/null | tail -10 | tee -a /var/log/glucosync-security.log || echo "None" | tee -a /var/log/glucosync-security.log

echo -e "\nFail2ban status:" | tee -a /var/log/glucosync-security.log
fail2ban-client status | tee -a /var/log/glucosync-security.log

echo -e "\nListening ports:" | tee -a /var/log/glucosync-security.log
ss -tuln | tee -a /var/log/glucosync-security.log

echo -e "\nUFW status:" | tee -a /var/log/glucosync-security.log
ufw status numbered | tee -a /var/log/glucosync-security.log

echo "=== End Security Scan ===" | tee -a /var/log/glucosync-security.log
EOF

    chmod +x /usr/local/bin/glucosync-security-scan.sh

    # Add cron job for daily security scan
    cat > /etc/cron.daily/glucosync-security << 'EOF'
#!/bin/bash
/usr/local/bin/glucosync-security-scan.sh
EOF
    chmod +x /etc/cron.daily/glucosync-security

    # Display security banner on login
    cat > /etc/update-motd.d/99-glucosync-security << 'EOF'
#!/bin/sh
echo ""
echo "🔒 GlucoSync Security Hardened System"
echo "======================================"
echo "Fail2ban: Active"
echo "UFW Firewall: Enabled"
echo "AppArmor: Enabled"
echo "Audit: Running"
echo ""
echo "Security Commands:"
echo "  fail2ban-client status       - Check fail2ban status"
echo "  fail2ban-client status sshd  - Check SSH jail"
echo "  ufw status                   - Check firewall status"
echo "  aa-status                    - Check AppArmor status"
echo "  auditctl -l                  - List audit rules"
echo "  lynis audit system           - Run security audit"
echo "  aide --check                 - Check file integrity"
echo ""
EOF
    chmod +x /etc/update-motd.d/99-glucosync-security

    echo_info "System hardening completed!"
}

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

    # Configure firewall for K3s control plane
    echo_info "Configuring firewall for K3s control plane..."
    ufw allow 6443/tcp comment 'K3s API server'
    ufw allow 2379:2380/tcp comment 'etcd client and peer'
    ufw allow 10250/tcp comment 'Kubelet API'
    ufw allow 10251/tcp comment 'kube-scheduler'
    ufw allow 10252/tcp comment 'kube-controller-manager'
    ufw allow 8472/udp comment 'Flannel VXLAN'
    ufw allow 51820/udp comment 'Flannel WireGuard IPv4'
    ufw allow 51821/udp comment 'Flannel WireGuard IPv6'
    ufw reload

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

    # Configure firewall for K3s worker
    echo_info "Configuring firewall for K3s worker..."
    ufw allow 10250/tcp comment 'Kubelet API'
    ufw allow 8472/udp comment 'Flannel VXLAN'
    ufw allow 51820/udp comment 'Flannel WireGuard IPv4'
    ufw allow 51821/udp comment 'Flannel WireGuard IPv6'
    ufw reload

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

    # Apply Longhorn configuration if exists
    if [[ -f "${K8S_BASE_DIR}/storage/longhorn/values.yaml" ]]; then
        kubectl apply -f "${K8S_BASE_DIR}/storage/longhorn/values.yaml"
    fi

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

    # Check if Helm is installed
    if ! command -v helm &> /dev/null; then
        echo_info "Installing Helm..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi

    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update

    # Install with or without custom values
    if [[ -f "${K8S_BASE_DIR}/networking/nginx-ingress/values.yaml" ]]; then
        helm install ingress-nginx ingress-nginx/ingress-nginx \
            --namespace ingress-nginx \
            --create-namespace \
            -f "${K8S_BASE_DIR}/networking/nginx-ingress/values.yaml"
    else
        helm install ingress-nginx ingress-nginx/ingress-nginx \
            --namespace ingress-nginx \
            --create-namespace
    fi

    echo_info "Waiting for Nginx Ingress to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx --timeout=300s

    # Allow HTTP/HTTPS through firewall
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    ufw reload

    echo_info "Nginx Ingress installed successfully"
}

# Function to create namespaces
create_namespaces() {
    echo_info "Creating namespaces..."
    
    if [[ ! -f "${K8S_BASE_DIR}/namespaces/namespaces.yaml" ]]; then
        echo_error "Namespaces file not found at: ${K8S_BASE_DIR}/namespaces/namespaces.yaml"
        exit 1
    fi
    
    kubectl apply -f "${K8S_BASE_DIR}/namespaces/namespaces.yaml"
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
    echo "0. Harden System Security (Run First!)"
    echo "1. Install K3s Control Plane"
    echo "2. Install K3s Worker Node"
    echo "3. Install Longhorn Storage"
    echo "4. Install cert-manager"
    echo "5. Install Nginx Ingress Controller"
    echo "6. Create Namespaces"
    echo "7. Install Postgres Operator"
    echo "8. Create Secrets"
    echo "9. Full Setup (Security + Control Plane)"
    echo "10. Exit"
    echo ""
}

full_setup() {
    echo_info "Starting full cluster setup..."
    harden_system
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
    echo ""
    echo_info "Run security audit: lynis audit system"
    echo_info "Check security status: /usr/local/bin/glucosync-security-scan.sh"
}

# Main loop
while true; do
    show_menu
    read -p "Enter your choice: " choice
    case $choice in
        0) harden_system ;;
        1) install_control_plane ;;
        2) install_worker ;;
        3) install_longhorn ;;
        4) install_cert_manager ;;
        5) install_nginx_ingress ;;
        6) create_namespaces ;;
        7) install_postgres_operator ;;
        8) create_secrets ;;
        9) full_setup ;;
        10) echo_info "Exiting..."; exit 0 ;;
        *) echo_error "Invalid choice" ;;
    esac
done
