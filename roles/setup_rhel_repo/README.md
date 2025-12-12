# RHEL/CentOS YUM Repository Setup Role

This Ansible role configures RHEL/CentOS systems to use a local YUM repository served via HTTP.

## Features

- Supports RHEL 7 (single repository) and RHEL 8+ (BaseOS + AppStream)
- Configures YUM repository from HTTP URL
- Automatic cache management
- Repository validation
- Backup of original repository configurations

## Requirements

- RHEL, CentOS, Rocky Linux, or AlmaLinux
- HTTP server providing repository access
- Network connectivity to repository server

## Role Variables

### Required Variables

- `enable_rhel_repo`: Enable/disable repository setup (default: `false`)
- `rhel_repo_url`: Repository server URL (required when enabled)

### Optional Variables

- `rhel_repo_type`: Repository type - `single` or `baseos_appstream` (default: `single`)
- `rhel_repo_file`: YUM repository configuration file path (default: `/etc/yum.repos.d/rhel-local-repo.repo`)
- `rhel_repo_id`: Repository ID prefix (default: `rhel-local-repo`)
- `rhel_repo_name`: Repository display name (default: `RHEL Local Repository`)
- `rhel_repo_enabled`: Enable repository (default: `1`)
- `rhel_repo_gpgcheck`: Enable GPG signature checking (default: `0`)
- `rhel_repo_priority`: Repository priority (default: `1`)
- `rhel_repo_clean_cache`: Clean YUM cache after setup (default: `true`)

## Repository Types

### Single Repository (`single`)

For RHEL 7 or custom directory-based repositories:

```yaml
rhel_repo_type: single
rhel_repo_url: http://192.168.1.100:8080/rhel-repo
```

This creates:
```ini
[rhel-local-repo]
name=RHEL Local Repository
baseurl=http://192.168.1.100:8080/rhel-repo
enabled=1
gpgcheck=0
```

### BaseOS + AppStream (`baseos_appstream`)

For RHEL 8+ with separate BaseOS and AppStream repositories:

```yaml
rhel_repo_type: baseos_appstream
rhel_repo_url: http://192.168.1.100:8080/rhel-repo
```

This creates:
```ini
[rhel-local-repo-baseos]
name=RHEL Local Repository - BaseOS
baseurl=http://192.168.1.100:8080/rhel-repo/BaseOS
enabled=1
gpgcheck=0

[rhel-local-repo-appstream]
name=RHEL Local Repository - AppStream
baseurl=http://192.168.1.100:8080/rhel-repo/AppStream
enabled=1
gpgcheck=0
```

## Example Playbook

### Basic Usage (RHEL 7 or Directory Repo)

```yaml
- hosts: rhel_servers
  roles:
    - role: setup_rhel_repo
      vars:
        enable_rhel_repo: true
        rhel_repo_url: http://192.168.1.100:8080/rhel-repo
        rhel_repo_type: single
```

### RHEL 8+ with BaseOS and AppStream

```yaml
- hosts: rhel8_servers
  roles:
    - role: setup_rhel_repo
      vars:
        enable_rhel_repo: true
        rhel_repo_url: http://192.168.1.100:8080/rhel-repo
        rhel_repo_type: baseos_appstream
```

### Custom Configuration

```yaml
- hosts: all
  roles:
    - role: setup_rhel_repo
      vars:
        enable_rhel_repo: true
        rhel_repo_url: http://repo.example.com:8080/rhel-repo
        rhel_repo_type: single
        rhel_repo_id: custom-repo
        rhel_repo_name: Custom RHEL Repository
        rhel_repo_priority: 10
```

## Setting Up Repository Server

Use the `scripts/manage-rhel-repo.sh` script to set up the repository server:

### ISO-based Repository

```bash
# Configure .env.rhel-repo
cp .env.rhel-repo.example .env.rhel-repo
nano .env.rhel-repo

# Set RHEL_REPO_TYPE=iso
# Set RHEL_REPO_ISO_PATH=/path/to/rhel.iso

# Setup repository from ISO
sudo ./scripts/manage-rhel-repo.sh setup-iso

# Install and start HTTP server
sudo ./scripts/manage-rhel-repo.sh httpd-install
```

### Directory-based Repository

```bash
# Configure .env.rhel-repo
cp .env.rhel-repo.example .env.rhel-repo
nano .env.rhel-repo

# Set RHEL_REPO_TYPE=directory
# Set RHEL_REPO_SOURCE_DIR=/path/to/rpms

# Setup repository from directory
sudo ./scripts/manage-rhel-repo.sh setup-directory

# Install and start HTTP server
sudo ./scripts/manage-rhel-repo.sh httpd-install
```

## Verification

After running the role, verify the repository is working:

```bash
# List repositories
yum repolist

# Check repository configuration
cat /etc/yum.repos.d/rhel-local-repo.repo

# Test package search
yum search vim
```

## Notes

- Original repository configurations are backed up to `/etc/yum.repos.d/backup/`
- The role only runs on RHEL-based systems (ansible_os_family == "RedHat")
- Repository priority of 1 means highest priority (lower number = higher priority)
- GPG checking is disabled by default for local repositories

## License

MIT

## Author

Created for Kubernetes kubeadm deployment automation
