#!/bin/bash
set -e

# Script to manage NFS server
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_ROOT}/.env.nfs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load environment variables from .env.nfs
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Error: .env.nfs file not found!${NC}"
    echo -e "${YELLOW}Please copy .env.nfs.example to .env.nfs and configure it.${NC}"
    echo "cp ${PROJECT_ROOT}/.env.nfs.example ${ENV_FILE}"
    exit 1
fi

# Load .env file
set -a
source "$ENV_FILE"
set +a

# Default values if not set in .env
NFS_EXPORT_OWNER="${NFS_EXPORT_OWNER:-root}"
NFS_EXPORT_GROUP="${NFS_EXPORT_GROUP:-root}"
NFS_EXPORT_MODE="${NFS_EXPORT_MODE:-0755}"
NFS_ENABLE_ON_BOOT="${NFS_ENABLE_ON_BOOT:-true}"

# Function to print usage
usage() {
    cat <<EOF
Usage: $0 {install|start|stop|restart|status|reload|show-exports|add-export|remove}

Commands:
  install       - Install NFS server packages
  start         - Start NFS server
  stop          - Stop NFS server
  restart       - Restart NFS server
  status        - Show NFS server status
  reload        - Reload exports without restarting
  show-exports  - Display current /etc/exports configuration
  add-export    - Add configured exports to /etc/exports
  remove        - Remove NFS server and exports

Environment variables are loaded from: $ENV_FILE
EOF
    exit 1
}

# Function to detect OS and set package manager
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        echo -e "${RED}Cannot detect OS${NC}"
        exit 1
    fi
}

# Function to install NFS server
install_nfs() {
    echo -e "${GREEN}==> Installing NFS server...${NC}"
    detect_os

    case $OS in
        ubuntu|debian)
            echo "Installing NFS server on Debian/Ubuntu..."
            apt-get update
            apt-get install -y nfs-kernel-server nfs-common
            ;;
        rhel|centos|rocky|almalinux)
            echo "Installing NFS server on RHEL/CentOS/Rocky..."
            yum install -y nfs-utils
            ;;
        *)
            echo -e "${RED}Unsupported OS: $OS${NC}"
            exit 1
            ;;
    esac

    echo -e "${GREEN}NFS server packages installed successfully${NC}"
}

# Function to create export directories
create_export_dirs() {
    echo -e "${BLUE}==> Creating export directories...${NC}"

    IFS=',' read -ra PATHS <<< "$NFS_EXPORT_PATHS"

    for path in "${PATHS[@]}"; do
        # Trim whitespace
        path=$(echo "$path" | xargs)

        if [ ! -d "$path" ]; then
            echo "Creating directory: $path"
            mkdir -p "$path"
        fi

        echo "Setting ownership: $NFS_EXPORT_OWNER:$NFS_EXPORT_GROUP"
        chown "$NFS_EXPORT_OWNER:$NFS_EXPORT_GROUP" "$path"

        echo "Setting permissions: $NFS_EXPORT_MODE"
        chmod "$NFS_EXPORT_MODE" "$path"
    done

    echo -e "${GREEN}Export directories created${NC}"
}

# Function to configure exports
configure_exports() {
    echo -e "${BLUE}==> Configuring /etc/exports...${NC}"

    # Backup existing exports
    if [ -f /etc/exports ]; then
        cp /etc/exports /etc/exports.backup.$(date +%Y%m%d_%H%M%S)
        echo "Backed up existing /etc/exports"
    fi

    # Parse paths and options
    IFS=',' read -ra PATHS <<< "$NFS_EXPORT_PATHS"
    IFS=',' read -ra OPTIONS <<< "$NFS_EXPORT_OPTIONS"

    # Clear managed section or create new file
    if ! grep -q "# BEGIN MANAGED NFS EXPORTS" /etc/exports 2>/dev/null; then
        echo "# BEGIN MANAGED NFS EXPORTS - DO NOT EDIT THIS SECTION MANUALLY" >> /etc/exports
        echo "# This section is managed by manage-nfs.sh script" >> /etc/exports
    else
        # Remove old managed section
        sed -i '/# BEGIN MANAGED NFS EXPORTS/,/# END MANAGED NFS EXPORTS/d' /etc/exports
        echo "# BEGIN MANAGED NFS EXPORTS - DO NOT EDIT THIS SECTION MANUALLY" >> /etc/exports
        echo "# This section is managed by manage-nfs.sh script" >> /etc/exports
    fi

    # Add new exports
    for i in "${!PATHS[@]}"; do
        path=$(echo "${PATHS[$i]}" | xargs)
        option="${OPTIONS[$i]:-${OPTIONS[0]}}"  # Use first option as default if not enough options
        option=$(echo "$option" | xargs)

        echo "$path $option" >> /etc/exports
        echo "Added export: $path $option"
    done

    echo "# END MANAGED NFS EXPORTS" >> /etc/exports

    echo -e "${GREEN}/etc/exports configured${NC}"
}

# Function to start NFS server
start_nfs() {
    echo -e "${GREEN}==> Starting NFS server...${NC}"
    detect_os

    case $OS in
        ubuntu|debian)
            systemctl start nfs-kernel-server
            if [ "$NFS_ENABLE_ON_BOOT" = "true" ]; then
                systemctl enable nfs-kernel-server
            fi
            ;;
        rhel|centos|rocky|almalinux)
            systemctl start nfs-server
            if [ "$NFS_ENABLE_ON_BOOT" = "true" ]; then
                systemctl enable nfs-server
            fi
            ;;
    esac

    # Export all shares
    exportfs -ra

    echo -e "${GREEN}NFS server started successfully${NC}"
    show_status
}

# Function to stop NFS server
stop_nfs() {
    echo -e "${YELLOW}==> Stopping NFS server...${NC}"
    detect_os

    case $OS in
        ubuntu|debian)
            systemctl stop nfs-kernel-server
            ;;
        rhel|centos|rocky|almalinux)
            systemctl stop nfs-server
            ;;
    esac

    echo -e "${GREEN}NFS server stopped${NC}"
}

# Function to restart NFS server
restart_nfs() {
    echo -e "${YELLOW}==> Restarting NFS server...${NC}"
    stop_nfs
    sleep 2
    start_nfs
}

# Function to reload exports
reload_exports() {
    echo -e "${BLUE}==> Reloading NFS exports...${NC}"
    exportfs -ra
    echo -e "${GREEN}Exports reloaded${NC}"
    exportfs -v
}

# Function to show status
show_status() {
    echo -e "${GREEN}==> NFS Server Status:${NC}"
    echo ""
    detect_os

    case $OS in
        ubuntu|debian)
            systemctl status nfs-kernel-server --no-pager || true
            ;;
        rhel|centos|rocky|almalinux)
            systemctl status nfs-server --no-pager || true
            ;;
    esac

    echo ""
    echo -e "${BLUE}==> Active Exports:${NC}"
    exportfs -v
}

# Function to show exports configuration
show_exports() {
    echo -e "${GREEN}==> Current /etc/exports configuration:${NC}"
    echo ""
    cat /etc/exports
}

# Function to add exports
add_export() {
    create_export_dirs
    configure_exports
    reload_exports
}

# Function to remove NFS server
remove_nfs() {
    echo -e "${RED}==> Removing NFS server...${NC}"

    read -p "This will stop NFS server and remove exports configuration. Continue? [y/N] " confirm
    if [ "$confirm" != "y" ]; then
        echo "Aborted"
        exit 0
    fi

    detect_os

    # Stop server
    stop_nfs

    # Backup and clear managed exports
    if [ -f /etc/exports ]; then
        cp /etc/exports /etc/exports.backup.removed.$(date +%Y%m%d_%H%M%S)
        sed -i '/# BEGIN MANAGED NFS EXPORTS/,/# END MANAGED NFS EXPORTS/d' /etc/exports
        echo -e "${YELLOW}Managed exports removed from /etc/exports${NC}"
        echo -e "${YELLOW}Backup saved to /etc/exports.backup.removed.*${NC}"
    fi

    echo -e "${GREEN}NFS server configuration removed${NC}"
    echo -e "${YELLOW}Note: NFS packages are still installed. Directories were not deleted.${NC}"
}

# Main script
case "${1:-}" in
    install)
        install_nfs
        create_export_dirs
        configure_exports
        start_nfs
        ;;
    start)
        start_nfs
        ;;
    stop)
        stop_nfs
        ;;
    restart)
        restart_nfs
        ;;
    status)
        show_status
        ;;
    reload)
        reload_exports
        ;;
    show-exports)
        show_exports
        ;;
    add-export)
        add_export
        ;;
    remove)
        remove_nfs
        ;;
    *)
        usage
        ;;
esac
