#!/bin/bash
set -e

# Script to manage local Docker registry
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_ROOT}/.env.registry"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load environment variables from .env.registry
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Error: .env.registry file not found!${NC}"
    echo -e "${YELLOW}Please copy .env.registry.example to .env.registry and configure it.${NC}"
    echo "cp ${PROJECT_ROOT}/.env.registry.example ${ENV_FILE}"
    exit 1
fi

# Load .env file
set -a
source "$ENV_FILE"
set +a

# Default values if not set in .env
REGISTRY_IMAGE="${REGISTRY_IMAGE:-registry:2}"
REGISTRY_CONTAINER_NAME="${REGISTRY_CONTAINER_NAME:-local-registry}"
REGISTRY_HOST_PORT="${REGISTRY_HOST_PORT:-80}"
REGISTRY_CONTAINER_PORT="${REGISTRY_CONTAINER_PORT:-5000}"
REGISTRY_DATA_DIR="${REGISTRY_DATA_DIR:-/opt/local-registry/data}"

# Function to print usage
usage() {
    cat <<EOF
Usage: $0 {start|stop|restart|status|remove|logs}

Commands:
  start    - Start the local registry container
  stop     - Stop the local registry container
  restart  - Restart the local registry container
  status   - Show registry container status
  remove   - Remove the registry container (stop first)
  logs     - Show registry container logs

Environment variables are loaded from: $ENV_FILE
EOF
    exit 1
}

# Function to check if container exists
container_exists() {
    nerdctl ps -a --format '{{.Names}}' | grep -q "^${REGISTRY_CONTAINER_NAME}$"
}

# Function to check if container is running
container_running() {
    nerdctl ps --format '{{.Names}}' | grep -q "^${REGISTRY_CONTAINER_NAME}$"
}

# Function to start registry
start_registry() {
    echo -e "${GREEN}==> Starting local registry...${NC}"

    # Ensure data directory exists
    echo "Creating data directory: $REGISTRY_DATA_DIR"
    mkdir -p "$REGISTRY_DATA_DIR"

    # Load image from tar if specified and exists
    if [ -n "$REGISTRY_IMAGE_TAR" ] && [ -f "$REGISTRY_IMAGE_TAR" ]; then
        echo "Loading registry image from: $REGISTRY_IMAGE_TAR"
        nerdctl load -i "$REGISTRY_IMAGE_TAR"
    fi

    # Check if container already exists
    if container_exists; then
        if container_running; then
            echo -e "${YELLOW}Registry container is already running${NC}"
            return 0
        else
            echo "Starting existing container..."
            nerdctl start "$REGISTRY_CONTAINER_NAME"
            echo -e "${GREEN}Registry started successfully${NC}"
            return 0
        fi
    fi

    # Build nerdctl run command
    CMD="nerdctl run -d --name $REGISTRY_CONTAINER_NAME"
    CMD="$CMD --restart always"
    CMD="$CMD -p ${REGISTRY_HOST_PORT}:${REGISTRY_CONTAINER_PORT}"
    CMD="$CMD -v ${REGISTRY_DATA_DIR}:/var/lib/registry"

    # Add additional arguments if specified
    if [ -n "$REGISTRY_ADDITIONAL_ARGS" ]; then
        CMD="$CMD $REGISTRY_ADDITIONAL_ARGS"
    fi

    CMD="$CMD $REGISTRY_IMAGE"

    echo "Running: $CMD"
    eval $CMD

    echo -e "${GREEN}Registry container created and started successfully${NC}"
    echo "Registry available at: http://localhost:${REGISTRY_HOST_PORT}"
}

# Function to stop registry
stop_registry() {
    echo -e "${YELLOW}==> Stopping local registry...${NC}"

    if ! container_exists; then
        echo -e "${RED}Registry container does not exist${NC}"
        return 1
    fi

    if ! container_running; then
        echo -e "${YELLOW}Registry container is not running${NC}"
        return 0
    fi

    nerdctl stop "$REGISTRY_CONTAINER_NAME"
    echo -e "${GREEN}Registry stopped successfully${NC}"
}

# Function to restart registry
restart_registry() {
    echo -e "${YELLOW}==> Restarting local registry...${NC}"
    stop_registry
    sleep 2
    start_registry
}

# Function to show status
show_status() {
    echo -e "${GREEN}==> Registry Status:${NC}"
    echo ""

    if container_exists; then
        nerdctl ps -a --filter "name=^${REGISTRY_CONTAINER_NAME}$" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo ""

        if container_running; then
            echo -e "${GREEN}Status: RUNNING${NC}"
            echo "Registry URL: http://localhost:${REGISTRY_HOST_PORT}"
            echo "Data directory: ${REGISTRY_DATA_DIR}"
        else
            echo -e "${YELLOW}Status: STOPPED${NC}"
        fi
    else
        echo -e "${RED}Status: NOT CREATED${NC}"
        echo "Run '$0 start' to create and start the registry"
    fi
}

# Function to remove registry
remove_registry() {
    echo -e "${RED}==> Removing local registry...${NC}"

    if ! container_exists; then
        echo -e "${YELLOW}Registry container does not exist${NC}"
        return 0
    fi

    if container_running; then
        echo "Stopping container first..."
        nerdctl stop "$REGISTRY_CONTAINER_NAME"
    fi

    nerdctl rm -f "$REGISTRY_CONTAINER_NAME"
    echo -e "${GREEN}Registry container removed successfully${NC}"
    echo -e "${YELLOW}Note: Data directory ${REGISTRY_DATA_DIR} was not deleted${NC}"
}

# Function to show logs
show_logs() {
    echo -e "${GREEN}==> Registry Logs:${NC}"

    if ! container_exists; then
        echo -e "${RED}Registry container does not exist${NC}"
        return 1
    fi

    nerdctl logs "$REGISTRY_CONTAINER_NAME"
}

# Main script
case "${1:-}" in
    start)
        start_registry
        ;;
    stop)
        stop_registry
        ;;
    restart)
        restart_registry
        ;;
    status)
        show_status
        ;;
    remove)
        remove_registry
        ;;
    logs)
        show_logs
        ;;
    *)
        usage
        ;;
esac
