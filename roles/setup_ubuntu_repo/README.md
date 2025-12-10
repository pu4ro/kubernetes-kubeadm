# Ubuntu APT Repository Setup Role

This Ansible role configures Ubuntu hosts to use a custom local APT repository served via HTTP.

## Requirements

- Target system must be running Ubuntu
- APT package manager
- Network access to the repository server

## Role Variables

Available variables are listed below, along with default values (see `defaults/main.yml`):

```yaml
# Enable/disable Ubuntu repository setup
enable_ubuntu_repo: false

# Repository server URL (Apache HTTP server)
# Example: http://192.168.1.100:8080/ubuntu-repo
ubuntu_repo_url: ""

# APT repository entry components
ubuntu_repo_components: "./"

# APT sources list file path
ubuntu_repo_sources_file: /etc/apt/sources.list.d/ubuntu-local-repo.list

# Repository options
ubuntu_repo_trusted: true

# Whether to update APT cache after adding repository
ubuntu_repo_update_cache: true
```

## Dependencies

None.

## Example Playbook

### Basic Usage

```yaml
- hosts: all
  roles:
    - role: setup_ubuntu_repo
      vars:
        enable_ubuntu_repo: true
        ubuntu_repo_url: "http://192.168.1.100:8080/ubuntu-repo"
```

### With Custom Configuration

```yaml
- hosts: workers
  roles:
    - role: setup_ubuntu_repo
      vars:
        enable_ubuntu_repo: true
        ubuntu_repo_url: "http://repo.example.com:8080/ubuntu-repo"
        ubuntu_repo_components: "main restricted"
        ubuntu_repo_trusted: true
        ubuntu_repo_update_cache: true
```

### In group_vars/all.yml

```yaml
# Ubuntu Repository Configuration
enable_ubuntu_repo: true
ubuntu_repo_url: "http://{{ hostvars[groups['installs'][0]].ansible_host }}:8080/ubuntu-repo"
```

## Usage with Makefile

After configuring the role, you can use it with tags:

```bash
# Apply only Ubuntu repository configuration
make tag-ubuntu-repo

# Include in full installation
make install
```

## Features

- ✅ Ubuntu-only validation (fails on non-Ubuntu systems)
- ✅ Automatic sources.list backup
- ✅ APT cache update with retries
- ✅ Repository accessibility verification
- ✅ Idempotent configuration
- ✅ Configurable trusted repository option

## Generated Files

The role creates the following file:

- `/etc/apt/sources.list.d/ubuntu-local-repo.list` - APT sources configuration

Example content:
```
# Ubuntu Local Repository
# Managed by Ansible - Do not edit manually
deb [trusted=yes ]http://192.168.1.100:8080/ubuntu-repo ./
```

## Apache Server Setup

To set up the Apache repository server, use the provided management script:

```bash
# Initialize configuration
make ubuntu-repo-init

# Edit .env.ubuntu-repo with your settings
# Then setup local repository
make ubuntu-repo-setup

# Install and configure Apache
make apache-repo-install

# Check status
make apache-repo-status
```

## License

MIT

## Author Information

Created for Kubernetes cluster deployment automation.
