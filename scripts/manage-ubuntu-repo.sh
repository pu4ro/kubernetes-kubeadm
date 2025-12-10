#!/bin/bash
set -e

# Script to manage Ubuntu local APT repository
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_ROOT}/.env.ubuntu-repo"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load environment variables from .env.ubuntu-repo
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Error: .env.ubuntu-repo file not found!${NC}"
    echo -e "${YELLOW}Please copy .env.ubuntu-repo.example to .env.ubuntu-repo and configure it.${NC}"
    echo "cp ${PROJECT_ROOT}/.env.ubuntu-repo.example ${ENV_FILE}"
    exit 1
fi

# Load .env file
set -a
source "$ENV_FILE"
set +a

# Default values if not set in .env
UBUNTU_REPO_SOURCE_DIR="${UBUNTU_REPO_SOURCE_DIR:-/root/repo}"
UBUNTU_REPO_TARGET_DIR="${UBUNTU_REPO_TARGET_DIR:-/usr/local/repo}"
UBUNTU_REPO_APT_LIST_FILE="${UBUNTU_REPO_APT_LIST_FILE:-/etc/apt/sources.list.d/local-repo.list}"
UBUNTU_REPO_APT_ENTRY="${UBUNTU_REPO_APT_ENTRY:-deb [trusted=yes] file:/usr/local/repo ./}"
UBUNTU_REPO_OWNER="${UBUNTU_REPO_OWNER:-_apt}"

# Apache defaults
APACHE_PACKAGE="${APACHE_PACKAGE:-apache2}"
APACHE_SERVICE="${APACHE_SERVICE:-apache2}"
APACHE_DOCUMENT_ROOT="${APACHE_DOCUMENT_ROOT:-/var/www/html}"
APACHE_REPO_SYMLINK_NAME="${APACHE_REPO_SYMLINK_NAME:-ubuntu-repo}"
APACHE_PORT="${APACHE_PORT:-8080}"
APACHE_VHOST_FILE="${APACHE_VHOST_FILE:-/etc/apache2/sites-available/ubuntu-repo.conf}"
APACHE_VHOST_ENABLED="${APACHE_VHOST_ENABLED:-/etc/apache2/sites-enabled/ubuntu-repo.conf}"

# Function to print usage
usage() {
    cat <<EOF
Usage: $0 {setup|remove|status|update-sources|apache-install|apache-start|apache-stop|apache-restart|apache-status|apache-remove}

Commands:
  Local Repository:
    setup           - Setup Ubuntu local repository (move, chown, configure APT)
    remove          - Remove local repository configuration
    status          - Show repository status
    update-sources  - Update APT sources list only

  Apache HTTP Server:
    apache-install  - Install and configure Apache to serve repository via HTTP
    apache-start    - Start Apache service
    apache-stop     - Stop Apache service
    apache-restart  - Restart Apache service
    apache-status   - Show Apache service status
    apache-remove   - Remove Apache configuration and optionally uninstall

Environment variables are loaded from: $ENV_FILE
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

# Function to setup repository
setup_repo() {
    check_root
    echo -e "${GREEN}==> Setting up Ubuntu local repository...${NC}"

    # Check if source directory exists
    if [ ! -d "$UBUNTU_REPO_SOURCE_DIR" ]; then
        echo -e "${RED}Error: Source directory does not exist: $UBUNTU_REPO_SOURCE_DIR${NC}"
        exit 1
    fi

    # Move repository to target directory
    echo -e "${BLUE}Moving repository from $UBUNTU_REPO_SOURCE_DIR to $UBUNTU_REPO_TARGET_DIR${NC}"
    if [ -d "$UBUNTU_REPO_TARGET_DIR" ]; then
        echo -e "${YELLOW}Warning: Target directory already exists. Removing...${NC}"
        rm -rf "$UBUNTU_REPO_TARGET_DIR"
    fi

    mv "$UBUNTU_REPO_SOURCE_DIR" "$UBUNTU_REPO_TARGET_DIR"
    echo -e "${GREEN}Repository moved successfully${NC}"

    # Change ownership
    echo -e "${BLUE}Changing ownership to ${UBUNTU_REPO_OWNER}${NC}"
    if id "$UBUNTU_REPO_OWNER" &>/dev/null; then
        chown -R "${UBUNTU_REPO_OWNER}:" "$UBUNTU_REPO_TARGET_DIR"
        echo -e "${GREEN}Ownership changed successfully${NC}"
    else
        echo -e "${YELLOW}Warning: User ${UBUNTU_REPO_OWNER} does not exist. Skipping chown...${NC}"
    fi

    # Configure APT sources
    echo -e "${BLUE}Configuring APT sources list${NC}"
    echo "$UBUNTU_REPO_APT_ENTRY" > "$UBUNTU_REPO_APT_LIST_FILE"
    echo -e "${GREEN}APT sources configured: $UBUNTU_REPO_APT_LIST_FILE${NC}"

    # Update APT cache
    echo -e "${BLUE}Updating APT cache...${NC}"
    apt-get update
    echo -e "${GREEN}APT cache updated successfully${NC}"

    echo ""
    echo -e "${GREEN}==> Ubuntu local repository setup completed!${NC}"
    echo -e "Repository location: ${BLUE}$UBUNTU_REPO_TARGET_DIR${NC}"
    echo -e "APT sources file: ${BLUE}$UBUNTU_REPO_APT_LIST_FILE${NC}"
}

# Function to remove repository
remove_repo() {
    check_root
    echo -e "${RED}==> Removing Ubuntu local repository configuration...${NC}"

    # Remove APT sources list
    if [ -f "$UBUNTU_REPO_APT_LIST_FILE" ]; then
        echo -e "${BLUE}Removing APT sources file: $UBUNTU_REPO_APT_LIST_FILE${NC}"
        rm -f "$UBUNTU_REPO_APT_LIST_FILE"
        echo -e "${GREEN}APT sources file removed${NC}"
    else
        echo -e "${YELLOW}APT sources file not found${NC}"
    fi

    # Update APT cache
    echo -e "${BLUE}Updating APT cache...${NC}"
    apt-get update
    echo -e "${GREEN}APT cache updated${NC}"

    echo ""
    echo -e "${YELLOW}Note: Repository directory ${UBUNTU_REPO_TARGET_DIR} was not deleted${NC}"
    echo -e "${YELLOW}To remove it manually, run: sudo rm -rf ${UBUNTU_REPO_TARGET_DIR}${NC}"
}

# Function to show status
show_status() {
    echo -e "${GREEN}==> Ubuntu Local Repository Status:${NC}"
    echo ""

    # Check repository directory
    echo -e "${BLUE}Repository Directory:${NC}"
    if [ -d "$UBUNTU_REPO_TARGET_DIR" ]; then
        echo -e "  Location: ${GREEN}$UBUNTU_REPO_TARGET_DIR${NC} ${GREEN}(EXISTS)${NC}"
        echo -e "  Owner: $(stat -c '%U:%G' "$UBUNTU_REPO_TARGET_DIR")"
        echo -e "  Packages: $(find "$UBUNTU_REPO_TARGET_DIR" -name '*.deb' 2>/dev/null | wc -l) .deb files"
    else
        echo -e "  Location: ${RED}$UBUNTU_REPO_TARGET_DIR${NC} ${RED}(NOT FOUND)${NC}"
    fi

    echo ""
    echo -e "${BLUE}APT Configuration:${NC}"
    if [ -f "$UBUNTU_REPO_APT_LIST_FILE" ]; then
        echo -e "  Sources file: ${GREEN}$UBUNTU_REPO_APT_LIST_FILE${NC} ${GREEN}(EXISTS)${NC}"
        echo -e "  Content:"
        cat "$UBUNTU_REPO_APT_LIST_FILE" | sed 's/^/    /'
    else
        echo -e "  Sources file: ${RED}$UBUNTU_REPO_APT_LIST_FILE${NC} ${RED}(NOT FOUND)${NC}"
    fi

    echo ""
    echo -e "${BLUE}Expected Configuration:${NC}"
    echo -e "  Source Dir: $UBUNTU_REPO_SOURCE_DIR"
    echo -e "  Target Dir: $UBUNTU_REPO_TARGET_DIR"
    echo -e "  Owner: $UBUNTU_REPO_OWNER"
    echo -e "  APT Entry: $UBUNTU_REPO_APT_ENTRY"
}

# Function to update APT sources only
update_sources() {
    check_root
    echo -e "${BLUE}==> Updating APT sources list only...${NC}"

    if [ ! -d "$UBUNTU_REPO_TARGET_DIR" ]; then
        echo -e "${RED}Error: Repository directory does not exist: $UBUNTU_REPO_TARGET_DIR${NC}"
        exit 1
    fi

    echo "$UBUNTU_REPO_APT_ENTRY" > "$UBUNTU_REPO_APT_LIST_FILE"
    echo -e "${GREEN}APT sources configured: $UBUNTU_REPO_APT_LIST_FILE${NC}"

    echo -e "${BLUE}Updating APT cache...${NC}"
    apt-get update
    echo -e "${GREEN}APT cache updated successfully${NC}"
}

# ===================================================================
# Apache HTTP Server Functions
# ===================================================================

# Function to install and configure Apache
apache_install() {
    check_root
    echo -e "${GREEN}==> Installing and configuring Apache HTTP server...${NC}"

    # Check if repository directory exists
    if [ ! -d "$UBUNTU_REPO_TARGET_DIR" ]; then
        echo -e "${RED}Error: Repository directory does not exist: $UBUNTU_REPO_TARGET_DIR${NC}"
        echo -e "${YELLOW}Please run '$0 setup' first to setup the repository${NC}"
        exit 1
    fi

    # Install Apache
    echo -e "${BLUE}Installing Apache package: $APACHE_PACKAGE${NC}"
    apt-get update
    apt-get install -y "$APACHE_PACKAGE"
    echo -e "${GREEN}Apache installed successfully${NC}"

    # Create symlink in web root
    local symlink_path="${APACHE_DOCUMENT_ROOT}/${APACHE_REPO_SYMLINK_NAME}"
    echo -e "${BLUE}Creating symlink: $symlink_path -> $UBUNTU_REPO_TARGET_DIR${NC}"
    
    if [ -L "$symlink_path" ] || [ -e "$symlink_path" ]; then
        echo -e "${YELLOW}Removing existing symlink/directory${NC}"
        rm -rf "$symlink_path"
    fi
    
    ln -s "$UBUNTU_REPO_TARGET_DIR" "$symlink_path"
    echo -e "${GREEN}Symlink created successfully${NC}"

    # Create Apache virtual host configuration
    echo -e "${BLUE}Creating Apache virtual host configuration${NC}"
    cat > "$APACHE_VHOST_FILE" <<EOF
<VirtualHost *:${APACHE_PORT}>
    ServerAdmin webmaster@localhost
    DocumentRoot ${APACHE_DOCUMENT_ROOT}

    <Directory ${APACHE_DOCUMENT_ROOT}>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    <Directory ${UBUNTU_REPO_TARGET_DIR}>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/ubuntu-repo-error.log
    CustomLog \${APACHE_LOG_DIR}/ubuntu-repo-access.log combined
</VirtualHost>
EOF
    echo -e "${GREEN}Virtual host configuration created${NC}"

    # Update ports.conf if needed
    echo -e "${BLUE}Configuring Apache to listen on port ${APACHE_PORT}${NC}"
    if ! grep -q "^Listen ${APACHE_PORT}" /etc/apache2/ports.conf; then
        echo "Listen ${APACHE_PORT}" >> /etc/apache2/ports.conf
        echo -e "${GREEN}Added port ${APACHE_PORT} to ports.conf${NC}"
    else
        echo -e "${YELLOW}Port ${APACHE_PORT} already configured${NC}"
    fi

    # Enable the site
    echo -e "${BLUE}Enabling virtual host${NC}"
    a2ensite ubuntu-repo.conf
    echo -e "${GREEN}Virtual host enabled${NC}"

    # Restart Apache
    echo -e "${BLUE}Restarting Apache service${NC}"
    systemctl restart "$APACHE_SERVICE"
    echo -e "${GREEN}Apache restarted successfully${NC}"

    echo ""
    echo -e "${GREEN}==> Apache HTTP server configured successfully!${NC}"
    echo -e "Repository URL: ${BLUE}http://<server-ip>:${APACHE_PORT}/${APACHE_REPO_SYMLINK_NAME}/${NC}"
    echo -e "To use this repository on clients, add to sources.list:"
    echo -e "${BLUE}deb [trusted=yes] http://<server-ip>:${APACHE_PORT}/${APACHE_REPO_SYMLINK_NAME} ./${NC}"
}

# Function to start Apache
apache_start() {
    check_root
    echo -e "${GREEN}==> Starting Apache service...${NC}"

    if ! systemctl is-active --quiet "$APACHE_SERVICE"; then
        systemctl start "$APACHE_SERVICE"
        echo -e "${GREEN}Apache started successfully${NC}"
    else
        echo -e "${YELLOW}Apache is already running${NC}"
    fi

    systemctl status "$APACHE_SERVICE" --no-pager
}

# Function to stop Apache
apache_stop() {
    check_root
    echo -e "${YELLOW}==> Stopping Apache service...${NC}"

    if systemctl is-active --quiet "$APACHE_SERVICE"; then
        systemctl stop "$APACHE_SERVICE"
        echo -e "${GREEN}Apache stopped successfully${NC}"
    else
        echo -e "${YELLOW}Apache is not running${NC}"
    fi
}

# Function to restart Apache
apache_restart() {
    check_root
    echo -e "${YELLOW}==> Restarting Apache service...${NC}"
    systemctl restart "$APACHE_SERVICE"
    echo -e "${GREEN}Apache restarted successfully${NC}"
    systemctl status "$APACHE_SERVICE" --no-pager
}

# Function to show Apache status
apache_status() {
    echo -e "${GREEN}==> Apache Service Status:${NC}"
    echo ""

    # Check if Apache is installed
    if ! command -v apache2 &> /dev/null; then
        echo -e "${RED}Apache is NOT installed${NC}"
        echo "Run '$0 apache-install' to install and configure Apache"
        return 1
    fi

    echo -e "${GREEN}Apache is installed${NC}"
    echo ""

    # Show service status
    echo -e "${BLUE}Service Status:${NC}"
    systemctl status "$APACHE_SERVICE" --no-pager || true
    echo ""

    # Show configuration
    echo -e "${BLUE}Configuration:${NC}"
    local symlink_path="${APACHE_DOCUMENT_ROOT}/${APACHE_REPO_SYMLINK_NAME}"
    
    if [ -L "$symlink_path" ]; then
        echo -e "  Symlink: ${GREEN}$symlink_path -> $(readlink $symlink_path)${NC}"
    else
        echo -e "  Symlink: ${RED}$symlink_path (NOT FOUND)${NC}"
    fi

    if [ -f "$APACHE_VHOST_FILE" ]; then
        echo -e "  VHost Config: ${GREEN}$APACHE_VHOST_FILE (EXISTS)${NC}"
    else
        echo -e "  VHost Config: ${RED}$APACHE_VHOST_FILE (NOT FOUND)${NC}"
    fi

    if [ -L "$APACHE_VHOST_ENABLED" ]; then
        echo -e "  VHost Enabled: ${GREEN}YES${NC}"
    else
        echo -e "  VHost Enabled: ${RED}NO${NC}"
    fi

    echo -e "  Port: ${BLUE}${APACHE_PORT}${NC}"
    echo ""

    # Show repository URL
    local server_ip=$(hostname -I | awk '{print $1}')
    echo -e "${BLUE}Repository Access:${NC}"
    echo -e "  URL: ${GREEN}http://${server_ip}:${APACHE_PORT}/${APACHE_REPO_SYMLINK_NAME}/${NC}"
    echo -e "  APT Entry: ${BLUE}deb [trusted=yes] http://${server_ip}:${APACHE_PORT}/${APACHE_REPO_SYMLINK_NAME} ./${NC}"
}

# Function to remove Apache configuration
apache_remove() {
    check_root
    echo -e "${RED}==> Removing Apache configuration...${NC}"

    # Disable site if enabled
    if [ -L "$APACHE_VHOST_ENABLED" ]; then
        echo -e "${BLUE}Disabling virtual host${NC}"
        a2dissite ubuntu-repo.conf || true
        echo -e "${GREEN}Virtual host disabled${NC}"
    fi

    # Remove virtual host configuration
    if [ -f "$APACHE_VHOST_FILE" ]; then
        echo -e "${BLUE}Removing virtual host configuration${NC}"
        rm -f "$APACHE_VHOST_FILE"
        echo -e "${GREEN}Virtual host configuration removed${NC}"
    fi

    # Remove symlink
    local symlink_path="${APACHE_DOCUMENT_ROOT}/${APACHE_REPO_SYMLINK_NAME}"
    if [ -L "$symlink_path" ]; then
        echo -e "${BLUE}Removing symlink: $symlink_path${NC}"
        rm -f "$symlink_path"
        echo -e "${GREEN}Symlink removed${NC}"
    fi

    # Ask about uninstalling Apache
    echo ""
    echo -e "${YELLOW}Do you want to uninstall Apache? [y/N]${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Uninstalling Apache${NC}"
        apt-get remove -y "$APACHE_PACKAGE"
        apt-get autoremove -y
        echo -e "${GREEN}Apache uninstalled${NC}"
    else
        echo -e "${YELLOW}Apache package kept installed${NC}"
        echo -e "${BLUE}Restarting Apache${NC}"
        systemctl restart "$APACHE_SERVICE" || true
    fi

    echo -e "${GREEN}Apache configuration removed${NC}"
}

# Main script
case "${1:-}" in
    setup)
        setup_repo
        ;;
    remove)
        remove_repo
        ;;
    status)
        show_status
        ;;
    update-sources)
        update_sources
        ;;
    apache-install)
        apache_install
        ;;
    apache-start)
        apache_start
        ;;
    apache-stop)
        apache_stop
        ;;
    apache-restart)
        apache_restart
        ;;
    apache-status)
        apache_status
        ;;
    apache-remove)
        apache_remove
        ;;
    *)
        usage
        ;;
esac
