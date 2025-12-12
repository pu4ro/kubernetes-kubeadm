#!/bin/bash
set -e

# Script to manage RHEL/CentOS local YUM repository
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
# Allow ENV_FILE to be overridden via environment variable
ENV_FILE="${ENV_FILE:-${PROJECT_ROOT}/.env.rhel-repo}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load environment variables from env file
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Error: Environment file not found: ${ENV_FILE}${NC}"
    echo -e "${YELLOW}Please create the configuration file from an example:${NC}"
    echo "  For ISO:       cp ${PROJECT_ROOT}/.env.rhel-repo-iso.example ${ENV_FILE}"
    echo "  For directory: cp ${PROJECT_ROOT}/.env.rhel-repo-directory.example ${ENV_FILE}"
    exit 1
fi

# Load .env file
set -a
source "$ENV_FILE"
set +a

# Repository type: iso, directory
RHEL_REPO_TYPE="${RHEL_REPO_TYPE:-directory}"

# ISO specific settings
RHEL_REPO_ISO_PATH="${RHEL_REPO_ISO_PATH:-}"
RHEL_REPO_ISO_MOUNT_POINT="${RHEL_REPO_ISO_MOUNT_POINT:-/mnt/rhel-iso}"

# Directory specific settings
RHEL_REPO_SOURCE_DIR="${RHEL_REPO_SOURCE_DIR:-/root/repo}"
RHEL_REPO_TARGET_DIR="${RHEL_REPO_TARGET_DIR:-/usr/local/repo}"

# Common settings
RHEL_REPO_FILE="${RHEL_REPO_FILE:-/etc/yum.repos.d/local-repo.repo}"
RHEL_REPO_ID="${RHEL_REPO_ID:-local-repo}"
RHEL_REPO_NAME="${RHEL_REPO_NAME:-Local Repository}"

# HTTP defaults
HTTPD_PACKAGE="${HTTPD_PACKAGE:-httpd}"
HTTPD_SERVICE="${HTTPD_SERVICE:-httpd}"
HTTPD_DOCUMENT_ROOT="${HTTPD_DOCUMENT_ROOT:-/var/www/html}"
HTTPD_REPO_SYMLINK_NAME="${HTTPD_REPO_SYMLINK_NAME:-rhel-repo}"
HTTPD_PORT="${HTTPD_PORT:-8080}"
HTTPD_VHOST_FILE="${HTTPD_VHOST_FILE:-/etc/httpd/conf.d/rhel-repo.conf}"

# Function to print usage
usage() {
    cat <<EOF
Usage: $0 {setup-iso|setup-directory|remove|status|update-repo-file|mount-iso|unmount-iso|httpd-install|httpd-start|httpd-stop|httpd-restart|httpd-status|httpd-remove}

Commands:
  Local Repository:
    setup-iso          - Setup repository from ISO file
    setup-directory    - Setup repository from directory (with createrepo)
    remove             - Remove local repository configuration
    status             - Show repository status
    update-repo-file   - Update YUM repository configuration file only
    mount-iso          - Mount ISO file only
    unmount-iso        - Unmount ISO file

  HTTP Server:
    httpd-install      - Install and configure httpd to serve repository via HTTP
    httpd-start        - Start httpd service
    httpd-stop         - Stop httpd service
    httpd-restart      - Restart httpd service
    httpd-status       - Show httpd service status
    httpd-remove       - Remove httpd configuration and optionally uninstall

Environment variables are loaded from: $ENV_FILE
Repository type (RHEL_REPO_TYPE): iso or directory
EOF
    exit 1
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        echo "Please run with sudo: sudo $0 $1"
        exit 1
    fi
}

# Function to mount ISO
mount_iso() {
    check_root
    echo -e "${GREEN}==> Mounting ISO file...${NC}"

    # Check if ISO file exists
    if [ ! -f "$RHEL_REPO_ISO_PATH" ]; then
        echo -e "${RED}Error: ISO file does not exist: $RHEL_REPO_ISO_PATH${NC}"
        exit 1
    fi

    # Create mount point if it doesn't exist
    if [ ! -d "$RHEL_REPO_ISO_MOUNT_POINT" ]; then
        echo -e "${BLUE}Creating mount point: $RHEL_REPO_ISO_MOUNT_POINT${NC}"
        mkdir -p "$RHEL_REPO_ISO_MOUNT_POINT"
    fi

    # Check if already mounted
    if mountpoint -q "$RHEL_REPO_ISO_MOUNT_POINT"; then
        echo -e "${YELLOW}ISO already mounted at $RHEL_REPO_ISO_MOUNT_POINT${NC}"
        return 0
    fi

    # Mount the ISO
    echo -e "${BLUE}Mounting ISO: $RHEL_REPO_ISO_PATH -> $RHEL_REPO_ISO_MOUNT_POINT${NC}"
    mount -o loop,ro "$RHEL_REPO_ISO_PATH" "$RHEL_REPO_ISO_MOUNT_POINT"
    echo -e "${GREEN}ISO mounted successfully${NC}"

    # Add to /etc/fstab if not already present
    if ! grep -q "$RHEL_REPO_ISO_PATH" /etc/fstab; then
        echo -e "${BLUE}Adding mount entry to /etc/fstab${NC}"
        echo "$RHEL_REPO_ISO_PATH $RHEL_REPO_ISO_MOUNT_POINT iso9660 loop,ro 0 0" >> /etc/fstab
        echo -e "${GREEN}Entry added to /etc/fstab for persistent mounting${NC}"
    fi
}

# Function to unmount ISO
unmount_iso() {
    check_root
    echo -e "${YELLOW}==> Unmounting ISO file...${NC}"

    # Check if mounted
    if ! mountpoint -q "$RHEL_REPO_ISO_MOUNT_POINT"; then
        echo -e "${YELLOW}ISO not mounted at $RHEL_REPO_ISO_MOUNT_POINT${NC}"
        return 0
    fi

    # Unmount
    echo -e "${BLUE}Unmounting: $RHEL_REPO_ISO_MOUNT_POINT${NC}"
    umount "$RHEL_REPO_ISO_MOUNT_POINT"
    echo -e "${GREEN}ISO unmounted successfully${NC}"

    # Remove from /etc/fstab
    if grep -q "$RHEL_REPO_ISO_PATH" /etc/fstab; then
        echo -e "${BLUE}Removing mount entry from /etc/fstab${NC}"
        sed -i "\|$RHEL_REPO_ISO_PATH|d" /etc/fstab
        echo -e "${GREEN}Entry removed from /etc/fstab${NC}"
    fi
}

# Function to setup repository from ISO
setup_iso_repo() {
    check_root
    echo -e "${GREEN}==> Setting up RHEL repository from ISO...${NC}"

    # Mount ISO first
    mount_iso

    # Verify mount point has repository data
    if [ ! -d "$RHEL_REPO_ISO_MOUNT_POINT/repodata" ]; then
        echo -e "${RED}Error: No repodata found in mounted ISO${NC}"
        echo -e "${YELLOW}Looking for repodata in common locations...${NC}"

        # Check common subdirectories
        for subdir in "BaseOS" "AppStream" "." "*"; do
            if [ -d "$RHEL_REPO_ISO_MOUNT_POINT/$subdir/repodata" ]; then
                echo -e "${GREEN}Found repodata in: $RHEL_REPO_ISO_MOUNT_POINT/$subdir${NC}"
            fi
        done
    fi

    # Create YUM repository configuration
    echo -e "${BLUE}Creating YUM repository configuration${NC}"

    # Check for BaseOS and AppStream (RHEL 8+)
    if [ -d "$RHEL_REPO_ISO_MOUNT_POINT/BaseOS/repodata" ] && [ -d "$RHEL_REPO_ISO_MOUNT_POINT/AppStream/repodata" ]; then
        cat > "$RHEL_REPO_FILE" <<EOF
[${RHEL_REPO_ID}-baseos]
name=${RHEL_REPO_NAME} - BaseOS
baseurl=file://${RHEL_REPO_ISO_MOUNT_POINT}/BaseOS
enabled=1
gpgcheck=0
priority=1

[${RHEL_REPO_ID}-appstream]
name=${RHEL_REPO_NAME} - AppStream
baseurl=file://${RHEL_REPO_ISO_MOUNT_POINT}/AppStream
enabled=1
gpgcheck=0
priority=1
EOF
        echo -e "${GREEN}Created repository configuration for RHEL 8+ (BaseOS + AppStream)${NC}"
    else
        # Single repository (RHEL 7 or custom)
        cat > "$RHEL_REPO_FILE" <<EOF
[${RHEL_REPO_ID}]
name=${RHEL_REPO_NAME}
baseurl=file://${RHEL_REPO_ISO_MOUNT_POINT}
enabled=1
gpgcheck=0
priority=1
EOF
        echo -e "${GREEN}Created repository configuration for single repository${NC}"
    fi

    echo -e "${GREEN}YUM repository configured: $RHEL_REPO_FILE${NC}"

    # Clean and rebuild YUM cache
    echo -e "${BLUE}Cleaning YUM cache...${NC}"
    yum clean all
    echo -e "${BLUE}Building YUM cache...${NC}"
    yum makecache
    echo -e "${GREEN}YUM cache built successfully${NC}"

    echo ""
    echo -e "${GREEN}==> RHEL repository from ISO setup completed!${NC}"
    echo -e "ISO file: ${BLUE}$RHEL_REPO_ISO_PATH${NC}"
    echo -e "Mount point: ${BLUE}$RHEL_REPO_ISO_MOUNT_POINT${NC}"
    echo -e "YUM configuration file: ${BLUE}$RHEL_REPO_FILE${NC}"
}

# Function to setup repository from directory
setup_directory_repo() {
    check_root
    echo -e "${GREEN}==> Setting up RHEL repository from directory...${NC}"

    # Check if source directory exists
    if [ ! -d "$RHEL_REPO_SOURCE_DIR" ]; then
        echo -e "${RED}Error: Source directory does not exist: $RHEL_REPO_SOURCE_DIR${NC}"
        exit 1
    fi

    # Check for RPM files
    rpm_count=$(find "$RHEL_REPO_SOURCE_DIR" -name "*.rpm" 2>/dev/null | wc -l)
    if [ "$rpm_count" -eq 0 ]; then
        echo -e "${YELLOW}Warning: No RPM files found in $RHEL_REPO_SOURCE_DIR${NC}"
    else
        echo -e "${GREEN}Found $rpm_count RPM files${NC}"
    fi

    # Move repository to target directory if different
    if [ "$RHEL_REPO_SOURCE_DIR" != "$RHEL_REPO_TARGET_DIR" ]; then
        echo -e "${BLUE}Moving repository from $RHEL_REPO_SOURCE_DIR to $RHEL_REPO_TARGET_DIR${NC}"
        if [ -d "$RHEL_REPO_TARGET_DIR" ]; then
            echo -e "${YELLOW}Warning: Target directory already exists. Removing...${NC}"
            rm -rf "$RHEL_REPO_TARGET_DIR"
        fi
        mv "$RHEL_REPO_SOURCE_DIR" "$RHEL_REPO_TARGET_DIR"
        echo -e "${GREEN}Repository moved successfully${NC}"
    else
        echo -e "${BLUE}Using directory in place: $RHEL_REPO_TARGET_DIR${NC}"
    fi

    # Install createrepo_c if not already installed
    if ! command -v createrepo_c &> /dev/null; then
        echo -e "${BLUE}Installing createrepo_c...${NC}"
        yum install -y createrepo_c
        echo -e "${GREEN}createrepo_c installed${NC}"
    fi

    # Create repository metadata
    echo -e "${BLUE}Creating repository metadata...${NC}"
    createrepo_c "$RHEL_REPO_TARGET_DIR"
    echo -e "${GREEN}Repository metadata created${NC}"

    # Create YUM repository configuration
    echo -e "${BLUE}Creating YUM repository configuration${NC}"
    cat > "$RHEL_REPO_FILE" <<EOF
[${RHEL_REPO_ID}]
name=${RHEL_REPO_NAME}
baseurl=file://${RHEL_REPO_TARGET_DIR}
enabled=1
gpgcheck=0
priority=1
EOF
    echo -e "${GREEN}YUM repository configured: $RHEL_REPO_FILE${NC}"

    # Clean YUM cache
    echo -e "${BLUE}Cleaning YUM cache...${NC}"
    yum clean all
    echo -e "${BLUE}Building YUM cache...${NC}"
    yum makecache
    echo -e "${GREEN}YUM cache built successfully${NC}"

    echo ""
    echo -e "${GREEN}==> RHEL repository from directory setup completed!${NC}"
    echo -e "Repository location: ${BLUE}$RHEL_REPO_TARGET_DIR${NC}"
    echo -e "YUM configuration file: ${BLUE}$RHEL_REPO_FILE${NC}"
}

# Function to remove repository
remove_repo() {
    check_root
    echo -e "${RED}==> Removing RHEL local repository configuration...${NC}"

    # Remove YUM repository file
    if [ -f "$RHEL_REPO_FILE" ]; then
        echo -e "${BLUE}Removing YUM repository file: $RHEL_REPO_FILE${NC}"
        rm -f "$RHEL_REPO_FILE"
        echo -e "${GREEN}YUM repository file removed${NC}"
    else
        echo -e "${YELLOW}YUM repository file not found${NC}"
    fi

    # If ISO type, unmount
    if [ "$RHEL_REPO_TYPE" = "iso" ]; then
        if mountpoint -q "$RHEL_REPO_ISO_MOUNT_POINT"; then
            unmount_iso
        fi
    fi

    # Clean YUM cache
    echo -e "${BLUE}Cleaning YUM cache...${NC}"
    yum clean all
    echo -e "${GREEN}YUM cache cleaned${NC}"

    echo ""
    if [ "$RHEL_REPO_TYPE" = "directory" ]; then
        echo -e "${YELLOW}Note: Repository directory ${RHEL_REPO_TARGET_DIR} was not deleted${NC}"
        echo -e "${YELLOW}To remove it manually, run: sudo rm -rf ${RHEL_REPO_TARGET_DIR}${NC}"
    fi
}

# Function to show status
show_status() {
    echo -e "${GREEN}==> RHEL Local Repository Status:${NC}"
    echo ""
    echo -e "${BLUE}Repository Type: ${YELLOW}${RHEL_REPO_TYPE}${NC}"
    echo ""

    if [ "$RHEL_REPO_TYPE" = "iso" ]; then
        # ISO Repository Status
        echo -e "${BLUE}ISO Configuration:${NC}"
        echo -e "  ISO Path: $RHEL_REPO_ISO_PATH"
        if [ -f "$RHEL_REPO_ISO_PATH" ]; then
            echo -e "  ISO File: ${GREEN}EXISTS${NC}"
            echo -e "  ISO Size: $(du -h "$RHEL_REPO_ISO_PATH" | cut -f1)"
        else
            echo -e "  ISO File: ${RED}NOT FOUND${NC}"
        fi

        echo ""
        echo -e "${BLUE}Mount Status:${NC}"
        if mountpoint -q "$RHEL_REPO_ISO_MOUNT_POINT"; then
            echo -e "  Mount Point: ${GREEN}$RHEL_REPO_ISO_MOUNT_POINT (MOUNTED)${NC}"
            echo -e "  Mount Type: $(mount | grep "$RHEL_REPO_ISO_MOUNT_POINT" | awk '{print $5}')"

            # Check for repositories in mount point
            if [ -d "$RHEL_REPO_ISO_MOUNT_POINT/BaseOS/repodata" ]; then
                echo -e "  BaseOS: ${GREEN}Found${NC}"
            fi
            if [ -d "$RHEL_REPO_ISO_MOUNT_POINT/AppStream/repodata" ]; then
                echo -e "  AppStream: ${GREEN}Found${NC}"
            fi
            if [ -d "$RHEL_REPO_ISO_MOUNT_POINT/repodata" ]; then
                echo -e "  Repodata: ${GREEN}Found${NC}"
            fi
        else
            echo -e "  Mount Point: ${RED}$RHEL_REPO_ISO_MOUNT_POINT (NOT MOUNTED)${NC}"
        fi

    else
        # Directory Repository Status
        echo -e "${BLUE}Repository Directory:${NC}"
        if [ -d "$RHEL_REPO_TARGET_DIR" ]; then
            echo -e "  Location: ${GREEN}$RHEL_REPO_TARGET_DIR${NC} ${GREEN}(EXISTS)${NC}"
            echo -e "  Owner: $(stat -c '%U:%G' "$RHEL_REPO_TARGET_DIR")"
            echo -e "  Packages: $(find "$RHEL_REPO_TARGET_DIR" -name '*.rpm' 2>/dev/null | wc -l) .rpm files"

            # Check for repodata
            if [ -d "$RHEL_REPO_TARGET_DIR/repodata" ]; then
                echo -e "  Metadata: ${GREEN}Present${NC} (repodata directory exists)"
            else
                echo -e "  Metadata: ${RED}Missing${NC} (run '$0 setup-directory' to create)"
            fi
        else
            echo -e "  Location: ${RED}$RHEL_REPO_TARGET_DIR${NC} ${RED}(NOT FOUND)${NC}"
        fi
    fi

    echo ""
    echo -e "${BLUE}YUM Configuration:${NC}"
    if [ -f "$RHEL_REPO_FILE" ]; then
        echo -e "  Repository file: ${GREEN}$RHEL_REPO_FILE${NC} ${GREEN}(EXISTS)${NC}"
        echo -e "  Content:"
        cat "$RHEL_REPO_FILE" | sed 's/^/    /'
    else
        echo -e "  Repository file: ${RED}$RHEL_REPO_FILE${NC} ${RED}(NOT FOUND)${NC}"
    fi

    echo ""
    echo -e "${BLUE}Expected Configuration:${NC}"
    if [ "$RHEL_REPO_TYPE" = "iso" ]; then
        echo -e "  ISO Path: $RHEL_REPO_ISO_PATH"
        echo -e "  Mount Point: $RHEL_REPO_ISO_MOUNT_POINT"
    else
        echo -e "  Source Dir: $RHEL_REPO_SOURCE_DIR"
        echo -e "  Target Dir: $RHEL_REPO_TARGET_DIR"
    fi
    echo -e "  Repository ID: $RHEL_REPO_ID"
    echo -e "  Repository Name: $RHEL_REPO_NAME"
}

# Function to update repository file only
update_repo_file() {
    check_root
    echo -e "${BLUE}==> Updating YUM repository configuration file only...${NC}"

    if [ "$RHEL_REPO_TYPE" = "iso" ]; then
        if ! mountpoint -q "$RHEL_REPO_ISO_MOUNT_POINT"; then
            echo -e "${RED}Error: ISO not mounted at $RHEL_REPO_ISO_MOUNT_POINT${NC}"
            exit 1
        fi

        # Check for BaseOS and AppStream
        if [ -d "$RHEL_REPO_ISO_MOUNT_POINT/BaseOS/repodata" ] && [ -d "$RHEL_REPO_ISO_MOUNT_POINT/AppStream/repodata" ]; then
            cat > "$RHEL_REPO_FILE" <<EOF
[${RHEL_REPO_ID}-baseos]
name=${RHEL_REPO_NAME} - BaseOS
baseurl=file://${RHEL_REPO_ISO_MOUNT_POINT}/BaseOS
enabled=1
gpgcheck=0
priority=1

[${RHEL_REPO_ID}-appstream]
name=${RHEL_REPO_NAME} - AppStream
baseurl=file://${RHEL_REPO_ISO_MOUNT_POINT}/AppStream
enabled=1
gpgcheck=0
priority=1
EOF
        else
            cat > "$RHEL_REPO_FILE" <<EOF
[${RHEL_REPO_ID}]
name=${RHEL_REPO_NAME}
baseurl=file://${RHEL_REPO_ISO_MOUNT_POINT}
enabled=1
gpgcheck=0
priority=1
EOF
        fi
    else
        if [ ! -d "$RHEL_REPO_TARGET_DIR" ]; then
            echo -e "${RED}Error: Repository directory does not exist: $RHEL_REPO_TARGET_DIR${NC}"
            exit 1
        fi

        cat > "$RHEL_REPO_FILE" <<EOF
[${RHEL_REPO_ID}]
name=${RHEL_REPO_NAME}
baseurl=file://${RHEL_REPO_TARGET_DIR}
enabled=1
gpgcheck=0
priority=1
EOF
    fi

    echo -e "${GREEN}YUM repository configured: $RHEL_REPO_FILE${NC}"

    echo -e "${BLUE}Cleaning YUM cache...${NC}"
    yum clean all
    yum makecache
    echo -e "${GREEN}YUM cache updated successfully${NC}"
}

# ===================================================================
# HTTP Server Functions
# ===================================================================

# Function to get repository path for httpd
get_repo_path() {
    if [ "$RHEL_REPO_TYPE" = "iso" ]; then
        echo "$RHEL_REPO_ISO_MOUNT_POINT"
    else
        echo "$RHEL_REPO_TARGET_DIR"
    fi
}

# Function to install and configure httpd
httpd_install() {
    check_root
    echo -e "${GREEN}==> Installing and configuring httpd server...${NC}"

    local repo_path=$(get_repo_path)

    # Check if repository is available
    if [ ! -d "$repo_path" ]; then
        echo -e "${RED}Error: Repository directory does not exist: $repo_path${NC}"
        echo -e "${YELLOW}Please run '$0 setup-iso' or '$0 setup-directory' first${NC}"
        exit 1
    fi

    # Install httpd
    echo -e "${BLUE}Installing httpd package: $HTTPD_PACKAGE${NC}"
    yum install -y "$HTTPD_PACKAGE"
    echo -e "${GREEN}httpd installed successfully${NC}"

    # Create symlink in web root
    local symlink_path="${HTTPD_DOCUMENT_ROOT}/${HTTPD_REPO_SYMLINK_NAME}"
    echo -e "${BLUE}Creating symlink: $symlink_path -> $repo_path${NC}"

    if [ -L "$symlink_path" ] || [ -e "$symlink_path" ]; then
        echo -e "${YELLOW}Removing existing symlink/directory${NC}"
        rm -rf "$symlink_path"
    fi

    ln -s "$repo_path" "$symlink_path"
    echo -e "${GREEN}Symlink created successfully${NC}"

    # Use a single shared VirtualHost configuration for all repositories
    local shared_vhost_file="/etc/httpd/conf.d/rhel-repos.conf"

    if [ ! -f "$shared_vhost_file" ]; then
        echo -e "${BLUE}Creating shared httpd virtual host configuration${NC}"
        cat > "$shared_vhost_file" <<EOF
# RHEL Repositories Virtual Host (Shared)
# Managed by Ansible - Do not edit manually
Listen ${HTTPD_PORT}

<VirtualHost *:${HTTPD_PORT}>
    ServerAdmin webmaster@localhost
    DocumentRoot ${HTTPD_DOCUMENT_ROOT}

    <Directory ${HTTPD_DOCUMENT_ROOT}>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    # Repository directories are added as symlinks in ${HTTPD_DOCUMENT_ROOT}
    # Each repository is accessible via http://server:${HTTPD_PORT}/repo-name/

    ErrorLog logs/rhel-repos-error.log
    CustomLog logs/rhel-repos-access.log combined
</VirtualHost>
EOF
        echo -e "${GREEN}Shared virtual host configuration created: $shared_vhost_file${NC}"
    else
        echo -e "${YELLOW}Shared virtual host configuration already exists${NC}"
    fi

    # Configure SELinux if enabled
    if command -v getenforce &> /dev/null && [ "$(getenforce)" != "Disabled" ]; then
        echo -e "${BLUE}Configuring SELinux contexts${NC}"
        semanage fcontext -a -t httpd_sys_content_t "${repo_path}(/.*)?" 2>/dev/null || true
        restorecon -Rv "$repo_path" 2>/dev/null || true
        echo -e "${GREEN}SELinux contexts configured${NC}"
    fi

    # Configure firewall if firewalld is running
    if systemctl is-active --quiet firewalld; then
        echo -e "${BLUE}Configuring firewall for port ${HTTPD_PORT}${NC}"
        firewall-cmd --permanent --add-port=${HTTPD_PORT}/tcp
        firewall-cmd --reload
        echo -e "${GREEN}Firewall configured${NC}"
    fi

    # Enable and start httpd
    echo -e "${BLUE}Enabling and starting httpd service${NC}"
    systemctl enable "$HTTPD_SERVICE"
    systemctl restart "$HTTPD_SERVICE"
    echo -e "${GREEN}httpd enabled and started successfully${NC}"

    echo ""
    echo -e "${GREEN}==> httpd server configured successfully!${NC}"
    local server_ip=$(hostname -I | awk '{print $1}')
    echo -e "Repository URL: ${BLUE}http://${server_ip}:${HTTPD_PORT}/${HTTPD_REPO_SYMLINK_NAME}/${NC}"
    echo ""
    echo -e "To use this repository on clients, create /etc/yum.repos.d/remote-repo.repo:"
    echo -e "${BLUE}---${NC}"

    if [ "$RHEL_REPO_TYPE" = "iso" ] && [ -d "$RHEL_REPO_ISO_MOUNT_POINT/BaseOS" ]; then
        echo -e "${BLUE}[remote-repo-baseos]"
        echo -e "name=Remote Repository - BaseOS"
        echo -e "baseurl=http://${server_ip}:${HTTPD_PORT}/${HTTPD_REPO_SYMLINK_NAME}/BaseOS"
        echo -e "enabled=1"
        echo -e "gpgcheck=0"
        echo ""
        echo -e "[remote-repo-appstream]"
        echo -e "name=Remote Repository - AppStream"
        echo -e "baseurl=http://${server_ip}:${HTTPD_PORT}/${HTTPD_REPO_SYMLINK_NAME}/AppStream"
        echo -e "enabled=1"
        echo -e "gpgcheck=0${NC}"
    else
        echo -e "${BLUE}[remote-repo]"
        echo -e "name=Remote Repository"
        echo -e "baseurl=http://${server_ip}:${HTTPD_PORT}/${HTTPD_REPO_SYMLINK_NAME}"
        echo -e "enabled=1"
        echo -e "gpgcheck=0${NC}"
    fi
    echo -e "${BLUE}---${NC}"
}

# Function to start httpd
httpd_start() {
    check_root
    echo -e "${GREEN}==> Starting httpd service...${NC}"

    if ! systemctl is-active --quiet "$HTTPD_SERVICE"; then
        systemctl start "$HTTPD_SERVICE"
        echo -e "${GREEN}httpd started successfully${NC}"
    else
        echo -e "${YELLOW}httpd is already running${NC}"
    fi

    systemctl status "$HTTPD_SERVICE" --no-pager
}

# Function to stop httpd
httpd_stop() {
    check_root
    echo -e "${YELLOW}==> Stopping httpd service...${NC}"

    if systemctl is-active --quiet "$HTTPD_SERVICE"; then
        systemctl stop "$HTTPD_SERVICE"
        echo -e "${GREEN}httpd stopped successfully${NC}"
    else
        echo -e "${YELLOW}httpd is not running${NC}"
    fi
}

# Function to restart httpd
httpd_restart() {
    check_root
    echo -e "${YELLOW}==> Restarting httpd service...${NC}"
    systemctl restart "$HTTPD_SERVICE"
    echo -e "${GREEN}httpd restarted successfully${NC}"
    systemctl status "$HTTPD_SERVICE" --no-pager
}

# Function to show httpd status
httpd_status() {
    echo -e "${GREEN}==> httpd Service Status:${NC}"
    echo ""

    # Check if httpd is installed
    if ! command -v httpd &> /dev/null; then
        echo -e "${RED}httpd is NOT installed${NC}"
        echo "Run '$0 httpd-install' to install and configure httpd"
        return 1
    fi

    echo -e "${GREEN}httpd is installed${NC}"
    echo ""

    # Show service status
    echo -e "${BLUE}Service Status:${NC}"
    systemctl status "$HTTPD_SERVICE" --no-pager || true
    echo ""

    # Show configuration
    echo -e "${BLUE}Configuration:${NC}"
    local symlink_path="${HTTPD_DOCUMENT_ROOT}/${HTTPD_REPO_SYMLINK_NAME}"
    local shared_vhost_file="/etc/httpd/conf.d/rhel-repos.conf"

    if [ -L "$symlink_path" ]; then
        echo -e "  Symlink: ${GREEN}$symlink_path -> $(readlink $symlink_path)${NC}"
    else
        echo -e "  Symlink: ${RED}$symlink_path (NOT FOUND)${NC}"
    fi

    if [ -f "$shared_vhost_file" ]; then
        echo -e "  Shared VHost Config: ${GREEN}$shared_vhost_file (EXISTS)${NC}"

        # Show all repository symlinks
        local repo_count=$(find "${HTTPD_DOCUMENT_ROOT}" -maxdepth 1 -type l -name "rhel-repo*" 2>/dev/null | wc -l)
        if [ "$repo_count" -gt 0 ]; then
            echo -e "  Active Repositories: ${GREEN}$repo_count${NC}"
            find "${HTTPD_DOCUMENT_ROOT}" -maxdepth 1 -type l -name "rhel-repo*" 2>/dev/null | while read link; do
                echo -e "    - $(basename $link) -> $(readlink $link)"
            done
        fi
    else
        echo -e "  Shared VHost Config: ${RED}$shared_vhost_file (NOT FOUND)${NC}"
    fi

    echo -e "  Port: ${BLUE}${HTTPD_PORT}${NC}"
    echo ""

    # Show repository URL
    local server_ip=$(hostname -I | awk '{print $1}')
    local repo_path=$(get_repo_path)
    echo -e "${BLUE}Repository Access:${NC}"
    echo -e "  Repository Type: ${YELLOW}${RHEL_REPO_TYPE}${NC}"
    echo -e "  URL: ${GREEN}http://${server_ip}:${HTTPD_PORT}/${HTTPD_REPO_SYMLINK_NAME}/${NC}"
    echo ""
    echo -e "  YUM Config:"

    if [ "$RHEL_REPO_TYPE" = "iso" ] && [ -d "$RHEL_REPO_ISO_MOUNT_POINT/BaseOS" ]; then
        echo -e "    ${BLUE}[remote-repo-baseos]${NC}"
        echo -e "    ${BLUE}name=Remote Repository - BaseOS${NC}"
        echo -e "    ${BLUE}baseurl=http://${server_ip}:${HTTPD_PORT}/${HTTPD_REPO_SYMLINK_NAME}/BaseOS${NC}"
        echo -e "    ${BLUE}enabled=1${NC}"
        echo -e "    ${BLUE}gpgcheck=0${NC}"
        echo ""
        echo -e "    ${BLUE}[remote-repo-appstream]${NC}"
        echo -e "    ${BLUE}name=Remote Repository - AppStream${NC}"
        echo -e "    ${BLUE}baseurl=http://${server_ip}:${HTTPD_PORT}/${HTTPD_REPO_SYMLINK_NAME}/AppStream${NC}"
        echo -e "    ${BLUE}enabled=1${NC}"
        echo -e "    ${BLUE}gpgcheck=0${NC}"
    else
        echo -e "    ${BLUE}[remote-repo]${NC}"
        echo -e "    ${BLUE}name=Remote Repository${NC}"
        echo -e "    ${BLUE}baseurl=http://${server_ip}:${HTTPD_PORT}/${HTTPD_REPO_SYMLINK_NAME}${NC}"
        echo -e "    ${BLUE}enabled=1${NC}"
        echo -e "    ${BLUE}gpgcheck=0${NC}"
    fi
}

# Function to remove httpd configuration
httpd_remove() {
    check_root
    echo -e "${RED}==> Removing httpd configuration for ${HTTPD_REPO_SYMLINK_NAME}...${NC}"

    local shared_vhost_file="/etc/httpd/conf.d/rhel-repos.conf"

    # Remove symlink
    local symlink_path="${HTTPD_DOCUMENT_ROOT}/${HTTPD_REPO_SYMLINK_NAME}"
    if [ -L "$symlink_path" ]; then
        echo -e "${BLUE}Removing symlink: $symlink_path${NC}"
        rm -f "$symlink_path"
        echo -e "${GREEN}Symlink removed${NC}"
    fi

    # Check if there are other repository symlinks in DocumentRoot
    local other_repos=$(find "${HTTPD_DOCUMENT_ROOT}" -maxdepth 1 -type l -name "rhel-repo*" 2>/dev/null | wc -l)

    if [ "$other_repos" -eq 0 ]; then
        # No other repositories, safe to remove shared VirtualHost and firewall rule
        echo -e "${YELLOW}No other RHEL repositories found${NC}"

        # Remove shared VirtualHost configuration
        if [ -f "$shared_vhost_file" ]; then
            echo -e "${BLUE}Removing shared virtual host configuration${NC}"
            rm -f "$shared_vhost_file"
            echo -e "${GREEN}Shared virtual host configuration removed${NC}"
        fi

        # Remove firewall rule if firewalld is running
        if systemctl is-active --quiet firewalld; then
            echo -e "${BLUE}Removing firewall rule for port ${HTTPD_PORT}${NC}"
            firewall-cmd --permanent --remove-port=${HTTPD_PORT}/tcp 2>/dev/null || true
            firewall-cmd --reload
            echo -e "${GREEN}Firewall rule removed${NC}"
        fi

        # Restart httpd to apply changes
        if systemctl is-active --quiet "$HTTPD_SERVICE"; then
            echo -e "${BLUE}Restarting httpd service${NC}"
            systemctl restart "$HTTPD_SERVICE"
            echo -e "${GREEN}httpd service restarted${NC}"
        fi

        # Ask about uninstalling httpd
        echo ""
        echo -e "${YELLOW}Do you want to uninstall httpd? [y/N]${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}Stopping and uninstalling httpd${NC}"
            systemctl stop "$HTTPD_SERVICE" 2>/dev/null || true
            yum remove -y "$HTTPD_PACKAGE"
            echo -e "${GREEN}httpd uninstalled${NC}"
        else
            echo -e "${YELLOW}httpd package kept installed${NC}"
        fi
    else
        echo -e "${YELLOW}Other RHEL repositories still exist ($other_repos found), keeping shared configuration${NC}"

        # Restart httpd to apply changes
        if systemctl is-active --quiet "$HTTPD_SERVICE"; then
            echo -e "${BLUE}Restarting httpd service${NC}"
            systemctl restart "$HTTPD_SERVICE"
            echo -e "${GREEN}httpd service restarted${NC}"
        fi
    fi

    echo -e "${GREEN}Repository ${HTTPD_REPO_SYMLINK_NAME} removed from httpd${NC}"
}

# Main script
case "${1:-}" in
    setup-iso)
        setup_iso_repo
        ;;
    setup-directory)
        setup_directory_repo
        ;;
    remove)
        remove_repo
        ;;
    status)
        show_status
        ;;
    update-repo-file)
        update_repo_file
        ;;
    mount-iso)
        mount_iso
        ;;
    unmount-iso)
        unmount_iso
        ;;
    httpd-install)
        httpd_install
        ;;
    httpd-start)
        httpd_start
        ;;
    httpd-stop)
        httpd_stop
        ;;
    httpd-restart)
        httpd_restart
        ;;
    httpd-status)
        httpd_status
        ;;
    httpd-remove)
        httpd_remove
        ;;
    *)
        usage
        ;;
esac
