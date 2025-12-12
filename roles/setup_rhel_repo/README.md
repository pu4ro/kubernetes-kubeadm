# RHEL/CentOS YUM Repository Setup Role

This Ansible role configures RHEL/CentOS systems to use local YUM repositories served via HTTP.

## Features

- **Supports multiple repositories** - Configure multiple repo sources simultaneously
- Supports RHEL 7 (single repository) and RHEL 8+ (BaseOS + AppStream)
- Configures YUM repository from HTTP URL
- Repository priority management
- Automatic cache management
- Repository validation
- Backup of original repository configurations

## Requirements

- RHEL, CentOS, Rocky Linux, or AlmaLinux
- HTTP server providing repository access
- Network connectivity to repository server

## Role Variables

### Multiple Repositories Configuration (Recommended)

Configure in `group_vars/all.yml`:

- `enable_rhel_repos`: Enable/disable multiple repositories setup (default: `false`)
- `rhel_repos`: List of repository configurations

Each repository in the list supports:
- `name`: Repository display name (required)
- `id`: Repository ID for config file (required)
- `url`: Repository server URL (required)
- `type`: Repository type - `single` or `baseos_appstream` (required)
- `enabled`: Enable repository (default: `1`)
- `gpgcheck`: Enable GPG signature checking (default: `0`)
- `priority`: Repository priority - lower number = higher priority (default: `99`)

### Legacy Single Repository Configuration (Deprecated)

- `enable_rhel_repo`: Enable/disable repository setup (default: `false`)
- `rhel_repo_url`: Repository server URL (required when enabled)
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

### Multiple Repositories (Recommended)

Configure in `group_vars/all.yml`:

```yaml
enable_rhel_repos: true
rhel_repos:
  # ISO-based repository with BaseOS and AppStream
  - name: "RHEL ISO Repository"
    id: "rhel-iso-repo"
    url: "http://192.168.135.71:8080/rhel-repo-iso/"
    type: "baseos_appstream"
    enabled: 1
    gpgcheck: 0
    priority: 1
  # Directory-based repository
  - name: "RHEL Custom Repository"
    id: "rhel-directory-repo"
    url: "http://192.168.135.71:8080/rhel-repo-directory/"
    type: "single"
    enabled: 1
    gpgcheck: 0
    priority: 2
  # Additional repository
  - name: "RHEL Extra Repository"
    id: "rhel-extra-repo"
    url: "http://192.168.135.72:8080/rhel-extra/"
    type: "single"
    enabled: 1
    gpgcheck: 0
    priority: 3
```

Then run with tag:

```bash
ansible-playbook site.yml --tags rhel-repo
```

### Single Repository (Legacy)

```yaml
- hosts: rhel_servers
  roles:
    - role: setup_rhel_repo
      vars:
        enable_rhel_repo: true
        rhel_repo_url: http://192.168.1.100:8080/rhel-repo
        rhel_repo_type: single
```

### RHEL 8+ with BaseOS and AppStream (Legacy)

```yaml
- hosts: rhel8_servers
  roles:
    - role: setup_rhel_repo
      vars:
        enable_rhel_repo: true
        rhel_repo_url: http://192.168.1.100:8080/rhel-repo
        rhel_repo_type: baseos_appstream
```

## Setting Up Repository Server

Use the Makefile commands to easily manage repository servers:

### ISO-based Repository

```bash
# Initialize ISO repository configuration
make rhel-repo-init-iso

# Edit configuration
nano .env.rhel-repo-iso
# Set RHEL_REPO_ISO_PATH=/path/to/rhel.iso

# Setup repository from ISO
make rhel-repo-setup-iso

# Install and start HTTP server
make httpd-repo-install-iso
```

### Directory-based Repository

```bash
# Initialize directory repository configuration
make rhel-repo-init-directory

# Edit configuration
nano .env.rhel-repo-directory
# Set RHEL_REPO_SOURCE_DIR=/path/to/rpms

# Setup repository from directory
make rhel-repo-setup-directory

# Install and start HTTP server
make httpd-repo-install-directory
```

### Managing HTTP Server

```bash
# Start httpd service
make httpd-repo-start

# Stop httpd service
make httpd-repo-stop

# Restart httpd service
make httpd-repo-restart

# Check httpd status
make httpd-repo-status

# Remove httpd configuration
make httpd-repo-remove
```

### Direct Script Usage (Alternative)

You can also use the scripts directly:

```bash
# ISO-based
ENV_FILE=.env.rhel-repo-iso sudo -E ./scripts/manage-rhel-repo.sh setup-iso
ENV_FILE=.env.rhel-repo-iso sudo -E ./scripts/manage-rhel-repo.sh httpd-install

# Directory-based
ENV_FILE=.env.rhel-repo-directory sudo -E ./scripts/manage-rhel-repo.sh setup-directory
ENV_FILE=.env.rhel-repo-directory sudo -E ./scripts/manage-rhel-repo.sh httpd-install
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
