#!/bin/bash

#############################################################################
# Kubernetes Cluster Setup Script (Without Ansible)
# This script prepares the system for Kubernetes installation
#############################################################################

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables from .env file if it exists
if [ -f "${SCRIPT_DIR}/.env" ]; then
    log_info "Loading configuration from .env file..."
    set -a
    source "${SCRIPT_DIR}/.env"
    set +a
fi

# Colors
RED='[0;31m'
GREEN='[0;32m'
YELLOW='[1;33m'
BLUE='[0;34m'
NC='[0m' # No Color

# Log functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Configuration (can be overridden by .env file)
KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.27.14}"
CONTAINERD_VERSION="${CONTAINERD_VERSION:-1.7.6}"
POD_SUBNET="${POD_SUBNET:-10.244.0.0/16}"
SERVICE_SUBNET="${SERVICE_SUBNET:-10.96.0.0/12}"
TIMEZONE="${TIMEZONE:-Asia/Seoul}"

# Master node settings
MASTER_IP="${MASTER_IP:-}"
KUBE_VIP_ADDRESS="${KUBE_VIP_ADDRESS:-192.168.135.30}"
KUBE_VIP_INTERFACE="${KUBE_VIP_INTERFACE:-ens18}"

# Repository settings - RHEL/CentOS
USE_LOCAL_REPO="${USE_LOCAL_REPO:-true}"
USE_ISO_REPO="${USE_ISO_REPO:-true}"
ISO_MOUNT_POINT="${ISO_MOUNT_POINT:-/mnt/cdrom}"
ISO_FILE_PATH="${ISO_FILE_PATH:-/root/rhel-9.4-x86_64-dvd.iso}"
YUM_REPO_DIR="${YUM_REPO_DIR:-/root/yum-repo}"
REPO_WEB_PORT="${REPO_WEB_PORT:-8080}"

# Repository settings - Ubuntu
USE_LOCAL_APT_REPO="${USE_LOCAL_APT_REPO:-true}"
APT_REPO_URL="${APT_REPO_URL:-http://192.168.135.1:8080/ubuntu}"
APT_REPO_MIRROR="${APT_REPO_MIRROR:-http://kr.archive.ubuntu.com/ubuntu}"
APT_REPO_DISTRIBUTION="${APT_REPO_DISTRIBUTION:-jammy}"
APT_COMPONENTS="${APT_COMPONENTS:-main restricted universe multiverse}"

# Registry settings (convert space-separated string to array)
if [ -n "${INSECURE_REGISTRIES:-}" ]; then
    IFS=' ' read -ra INSECURE_REGISTRIES <<< "${INSECURE_REGISTRIES}"
else
    INSECURE_REGISTRIES=(
        "cr.makina.rocks"
        "harbor.runway.test"
    )
fi

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Detect OS
detect_os() {
    log_step "Detecting Operating System"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        log_info "OS: $OS $OS_VERSION"
    else
        log_error "Cannot detect OS"
        exit 1
    fi
}

# Get local IP
get_local_ip() {
    MASTER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)
    log_info "Local IP: $MASTER_IP"
}

# Step 1: Configure repository
configure_repository() {
    log_step "Step 1: Configuring Repository"

    if [[ "$OS" == "rhel" ]] || [[ "$OS" == "centos" ]] || [[ "$OS" == "rocky" ]]; then
        configure_rhel_repo
    elif [[ "$OS" == "ubuntu" ]]; then
        configure_ubuntu_repo
    fi
}

configure_rhel_repo() {
    log_info "Configuring RHEL/CentOS repository"

    # Remove existing repo files
    rm -f /etc/yum.repos.d/*.repo

    if [[ "$USE_ISO_REPO" == "true" ]]; then
        # Mount ISO if not mounted
        if ! mountpoint -q "$ISO_MOUNT_POINT"; then
            log_info "Mounting ISO..."
            mkdir -p "$ISO_MOUNT_POINT"
            mount -o loop,ro "$ISO_FILE_PATH" "$ISO_MOUNT_POINT" || log_warn "Failed to mount ISO"
        fi

        # Configure ISO repository
        cat > /etc/yum.repos.d/local-iso.repo <<EOF
[local-iso-baseos]
name=Local ISO BaseOS Repository
baseurl=file://$ISO_MOUNT_POINT/BaseOS
enabled=1
gpgcheck=0
priority=1

[local-iso-appstream]
name=Local ISO AppStream Repository
baseurl=file://$ISO_MOUNT_POINT/AppStream
enabled=1
gpgcheck=0
priority=1
EOF
        log_info "ISO repository configured"
    fi

    if [[ "$USE_LOCAL_REPO" == "true" ]] && [[ -d "$YUM_REPO_DIR" ]]; then
        # Configure yum-repo directory
        cat > /etc/yum.repos.d/local-yum.repo <<EOF
[local-yum-repo]
name=Local YUM Repository
baseurl=file://$YUM_REPO_DIR
enabled=1
gpgcheck=0
priority=1
EOF
        log_info "Local YUM repository configured"
    fi

    yum clean all
    log_info "Repository configuration complete"
}

configure_ubuntu_repo() {
    log_info "Configuring Ubuntu repository"
    
    # Backup original sources.list
    if [ -f /etc/apt/sources.list ] && [ ! -f /etc/apt/sources.list.backup ]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.backup
        log_info "Backed up original sources.list"
    fi
    
    if [[ "$USE_LOCAL_APT_REPO" == "true" ]]; then
        log_info "Configuring local APT repository..."
        cat > /etc/apt/sources.list <<EOF
# Local APT Repository
deb [trusted=yes] $APT_REPO_URL $APT_REPO_DISTRIBUTION $APT_COMPONENTS
deb [trusted=yes] $APT_REPO_URL $APT_REPO_DISTRIBUTION-updates $APT_COMPONENTS
deb [trusted=yes] $APT_REPO_URL $APT_REPO_DISTRIBUTION-backports $APT_COMPONENTS
deb [trusted=yes] $APT_REPO_URL $APT_REPO_DISTRIBUTION-security $APT_COMPONENTS
EOF
        log_info "Local APT repository configured"
    else
        log_info "Configuring mirror APT repository..."
        cat > /etc/apt/sources.list <<EOF
# Ubuntu Mirror Repository
deb $APT_REPO_MIRROR $APT_REPO_DISTRIBUTION $APT_COMPONENTS
deb $APT_REPO_MIRROR $APT_REPO_DISTRIBUTION-updates $APT_COMPONENTS
deb $APT_REPO_MIRROR $APT_REPO_DISTRIBUTION-backports $APT_COMPONENTS
deb $APT_REPO_MIRROR $APT_REPO_DISTRIBUTION-security $APT_COMPONENTS
EOF
        log_info "Mirror APT repository configured"
    fi
    
    apt-get update
    log_info "Repository configuration complete"
}

# Step 2: Install required packages
install_packages() {
    log_step "Step 2: Installing Required Packages"

    if [[ "$OS" == "rhel" ]] || [[ "$OS" == "centos" ]] || [[ "$OS" == "rocky" ]]; then
        log_info "Installing packages via yum/dnf..."
        yum install -y \
            curl \
            wget \
            vim \
            net-tools \
            bash-completion \
            yum-utils \
            device-mapper-persistent-data \
            lvm2 \
            chrony \
            socat \
            conntrack \
            ipvsadm \
            ipset \
            tar \
            bzip2 \
            || log_warn "Some packages failed to install"
    elif [[ "$OS" == "ubuntu" ]]; then
        log_info "Installing packages via apt..."
        apt-get install -y \
            apt-transport-https \
            ca-certificates \
            curl \
            software-properties-common \
            gnupg \
            lsb-release \
            chrony \
            socat \
            conntrack \
            ipvsadm \
            ipset \
            || log_warn "Some packages failed to install"
    fi

    log_info "Package installation complete"
}

# Step 3: Configure system settings
configure_system() {
    log_step "Step 3: Configuring System Settings"

    # Disable SELinux (RHEL/CentOS)
    if [[ "$OS" == "rhel" ]] || [[ "$OS" == "centos" ]] || [[ "$OS" == "rocky" ]]; then
        log_info "Disabling SELinux..."
        setenforce 0 2>/dev/null || true
        sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
    fi

    # Disable firewall (or configure it properly)
    log_info "Stopping firewall..."
    systemctl stop firewalld 2>/dev/null || true
    systemctl disable firewalld 2>/dev/null || true
    systemctl stop ufw 2>/dev/null || true
    systemctl disable ufw 2>/dev/null || true

    # Disable swap
    log_info "Disabling swap..."
    swapoff -a
    sed -i '/swap/d' /etc/fstab

    # Set timezone
    log_info "Setting timezone to $TIMEZONE..."
    timedatectl set-timezone "$TIMEZONE"

    # Configure hosts file
    log_info "Configuring /etc/hosts..."
    if ! grep -q "$(hostname)" /etc/hosts; then
        echo "$MASTER_IP $(hostname)" >> /etc/hosts
    fi

    log_info "System configuration complete"
}

# Step 4: Configure sysctl parameters
configure_sysctl() {
    log_step "Step 4: Configuring Kernel Parameters"

    log_info "Setting sysctl parameters for Kubernetes..."

    cat > /etc/sysctl.d/99-kubernetes.conf <<EOF
# Enable IP forwarding
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# Bridge network
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1

# Disable IPv6 (optional)
# net.ipv6.conf.all.disable_ipv6 = 0
# net.ipv6.conf.default.disable_ipv6 = 0

# Maximum number of connections
net.netfilter.nf_conntrack_max = 1000000
net.nf_conntrack_max = 1000000

# File descriptors
fs.file-max = 2097152
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288

# ARP cache
net.ipv4.neigh.default.gc_thresh1 = 1024
net.ipv4.neigh.default.gc_thresh2 = 4096
net.ipv4.neigh.default.gc_thresh3 = 8192
EOF

    # Load br_netfilter module
    modprobe br_netfilter
    modprobe overlay

    cat > /etc/modules-load.d/k8s.conf <<EOF
br_netfilter
overlay
EOF

    # Apply sysctl settings
    sysctl -p /etc/sysctl.d/99-kubernetes.conf

    log_info "Kernel parameters configured"
}

# Step 5: Install and configure Containerd
install_containerd() {
    log_step "Step 5: Installing Containerd"

    if [[ "$OS" == "rhel" ]] || [[ "$OS" == "centos" ]] || [[ "$OS" == "rocky" ]]; then
        log_info "Installing containerd via yum..."
        yum install -y containerd.io || yum install -y containerd
    elif [[ "$OS" == "ubuntu" ]]; then
        log_info "Installing containerd via apt..."
        apt-get install -y containerd.io || apt-get install -y containerd
    fi

    # Configure containerd
    log_info "Configuring containerd..."
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml

    # Enable systemd cgroup driver
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

    # Configure insecure registries
    if [ ${#INSECURE_REGISTRIES[@]} -gt 0 ]; then
        log_info "Configuring insecure registries..."
        for registry in "${INSECURE_REGISTRIES[@]}"; do
            log_info "  - $registry"
        done
    fi

    # Restart containerd
    systemctl daemon-reload
    systemctl enable containerd
    systemctl restart containerd

    log_info "Containerd installation complete"
}

# Step 6: Configure Chrony (NTP)
configure_chrony() {
    log_step "Step 6: Configuring Time Synchronization"

    log_info "Configuring chrony..."

    if [[ "$OS" == "rhel" ]] || [[ "$OS" == "centos" ]] || [[ "$OS" == "rocky" ]]; then
        systemctl enable chronyd
        systemctl start chronyd
    elif [[ "$OS" == "ubuntu" ]]; then
        systemctl enable chrony
        systemctl start chrony
    fi

    # Check time sync status
    chronyc tracking || timedatectl status

    log_info "Time synchronization configured"
}

# Step 7: Install Kubernetes packages
install_kubernetes() {
    log_step "Step 7: Installing Kubernetes Packages"

    if [[ "$OS" == "rhel" ]] || [[ "$OS" == "centos" ]] || [[ "$OS" == "rocky" ]]; then
        install_k8s_rhel
    elif [[ "$OS" == "ubuntu" ]]; then
        install_k8s_ubuntu
    fi
}

install_k8s_rhel() {
    log_info "Installing Kubernetes packages for RHEL/CentOS..."

    # Add Kubernetes repository
    cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.27/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.27/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

    # Install Kubernetes packages
    K8S_VERSION="${KUBERNETES_VERSION}-0"
    yum install -y \
        kubelet-${K8S_VERSION} \
        kubeadm-${K8S_VERSION} \
        kubectl-${K8S_VERSION} \
        --disableexcludes=kubernetes || log_warn "Failed to install specific K8s version"

    # Enable kubelet
    systemctl enable kubelet

    log_info "Kubernetes packages installed"
}

install_k8s_ubuntu() {
    log_info "Installing Kubernetes packages for Ubuntu..."

    # Add Kubernetes repository
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.27/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.27/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

    apt-get update

    K8S_VERSION="${KUBERNETES_VERSION}-*"
    apt-get install -y \
        kubelet=${K8S_VERSION} \
        kubeadm=${K8S_VERSION} \
        kubectl=${K8S_VERSION}

    apt-mark hold kubelet kubeadm kubectl

    log_info "Kubernetes packages installed"
}

# Step 8: Setup kubectl bash completion and environment
setup_kubectl_completion() {
    log_step "Step 8: Setting up kubectl completion and environment"

    # Setup comprehensive PATH if not already configured
    if ! grep -q "# Kubernetes environment PATH" ~/.bashrc; then
        log_info "Configuring comprehensive PATH..."
        cat >> ~/.bashrc <<'EOF'

# Kubernetes environment PATH
export PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin:/root/bin:$PATH"
EOF
    fi

    # Setup kubectl completion
    kubectl completion bash > /etc/bash_completion.d/kubectl 2>/dev/null || true

    # Add kubectl aliases and completion to ~/.bashrc
    if ! grep -q "alias k=kubectl" ~/.bashrc; then
        log_info "Adding kubectl aliases..."
        cat >> ~/.bashrc <<'EOF'

# Kubernetes aliases
alias k=kubectl
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias kga='kubectl get all'
alias kgpa='kubectl get pods -A'
complete -F __start_kubectl k
EOF
    fi

    log_info "kubectl completion and environment configured"
    log_info "Run 'source ~/.bashrc' to apply changes to current session"
}

# Display summary
display_summary() {
    log_step "Installation Summary"

    echo ""
    echo -e "${GREEN}✓ System prepared for Kubernetes installation${NC}"
    echo ""
    echo -e "${BLUE}System Information:${NC}"
    echo "  OS: $OS $OS_VERSION"
    echo "  Hostname: $(hostname)"
    echo "  IP Address: $MASTER_IP"
    echo ""
    echo -e "${BLUE}Installed Versions:${NC}"
    echo "  Containerd: $(containerd --version 2>/dev/null | awk '{print $3}' || echo 'N/A')"
    echo "  Kubeadm: $(kubeadm version -o short 2>/dev/null || echo 'N/A')"
    echo "  Kubelet: $(kubelet --version 2>/dev/null | awk '{print $2}' || echo 'N/A')"
    echo "  Kubectl: $(kubectl version --client -o yaml 2>/dev/null | grep gitVersion | awk '{print $2}' || echo 'N/A')"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. Initialize master node:"
    echo "     ${GREEN}kubeadm init --pod-network-cidr=$POD_SUBNET --service-cidr=$SERVICE_SUBNET${NC}"
    echo ""
    echo "  2. Configure kubectl for your user:"
    echo "     ${GREEN}mkdir -p \$HOME/.kube${NC}"
    echo "     ${GREEN}cp /etc/kubernetes/admin.conf \$HOME/.kube/config${NC}"
    echo "     ${GREEN}chown \$(id -u):\$(id -g) \$HOME/.kube/config${NC}"
    echo ""
    echo "  3. Install network plugin (e.g., Flannel):"
    echo "     ${GREEN}kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml${NC}"
    echo ""
}

# Main execution
main() {
    log_step "Kubernetes Cluster Setup Script"
    echo "This script will prepare your system for Kubernetes installation"
    echo ""

    check_root
    detect_os
    get_local_ip

    # Run all steps
    configure_repository
    install_packages
    configure_system
    configure_sysctl
    install_containerd
    configure_chrony
    install_kubernetes
    setup_kubectl_completion

    display_summary

    log_info "${GREEN}Setup completed successfully!${NC}"
}

# Run main function
main "$@"
