#!/bin/bash

# Ansible Ad-hoc Command Wrapper
# Usage: ./run-command.sh "COMMAND" [TARGET_GROUP] [OPTIONS]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
INVENTORY="${PROJECT_ROOT}/inventory.ini"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    cat << EOF
${GREEN}Ansible Ad-hoc Command Wrapper${NC}

Usage: $0 "COMMAND" [TARGET_GROUP] [OPTIONS]

Arguments:
  COMMAND        The command to execute on remote hosts (required)
  TARGET_GROUP   Target host group from inventory (default: all)
  OPTIONS        Additional ansible options (optional)

Examples:
  # Run uptime on all hosts
  $0 "uptime"

  # Run df command on master nodes
  $0 "df -h" masters

  # Check memory on workers with custom options
  $0 "free -m" workers "-f 10"

  # Run command as specific user
  $0 "whoami" all "--become-user=nginx"

  # Check service status
  $0 "systemctl status kubelet" all

Common Target Groups:
  all       - All hosts in inventory
  masters   - All master nodes
  workers   - All worker nodes
  master1   - First master node only

Common Options:
  -f N      - Fork N parallel processes (default: 5)
  -v        - Verbose mode
  -vv       - More verbose
  -vvv      - Very verbose (connection debugging)
  --check   - Dry run mode
EOF
    exit 1
}

# Check if command is provided
if [ $# -lt 1 ]; then
    echo -e "${RED}Error: Command argument is required${NC}"
    echo ""
    usage
fi

COMMAND="$1"
TARGET="${2:-all}"
EXTRA_OPTS="${3:-}"

# Check if inventory file exists
if [ ! -f "$INVENTORY" ]; then
    echo -e "${RED}Error: Inventory file not found: $INVENTORY${NC}"
    exit 1
fi

# Display execution info
echo -e "${YELLOW}========================================${NC}"
echo -e "${GREEN}Ansible Ad-hoc Command Execution${NC}"
echo -e "${YELLOW}========================================${NC}"
echo -e "Command:  ${GREEN}$COMMAND${NC}"
echo -e "Target:   ${GREEN}$TARGET${NC}"
echo -e "Inventory: ${GREEN}$INVENTORY${NC}"
if [ -n "$EXTRA_OPTS" ]; then
    echo -e "Options:  ${GREEN}$EXTRA_OPTS${NC}"
fi
echo -e "${YELLOW}========================================${NC}"
echo ""

# Execute ansible ad-hoc command
ansible "$TARGET" \
    -i "$INVENTORY" \
    -m shell \
    -a "$COMMAND" \
    -b \
    $EXTRA_OPTS

EXIT_CODE=$?

# Display result
echo ""
echo -e "${YELLOW}========================================${NC}"
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}Command executed successfully${NC}"
else
    echo -e "${RED}Command failed with exit code: $EXIT_CODE${NC}"
fi
echo -e "${YELLOW}========================================${NC}"

exit $EXIT_CODE
