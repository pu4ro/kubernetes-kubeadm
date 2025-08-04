# kubernetes-kubeadm

## Optimized Kubernetes Cluster Deployment with Ansible

This project provides an optimized, centralized approach to deploying Kubernetes clusters on **Ubuntu** and **CentOS** systems using kubeadm.

### ✨ Key Features

- **Multi-OS Support**: Seamless deployment on Ubuntu/Debian and CentOS/RHEL systems
- **Centralized Package Management**: All OS-specific packages managed in `group_vars/all.yml`
- **Flexible Configuration**: Easy customization of packages and components per environment
- **OS Compatibility Validation**: Automatic system validation before deployment
- **Optimized Performance**: Removed duplications and improved error handling

### 🚀 Quick Start

#### 1. Basic Deployment
```bash
ansible-playbook -i inventory.ini site.yml
```

#### 2. Deploy with specific tags
```bash
# Only validation and system setup
ansible-playbook -i inventory.ini site.yml --tags "validation,system_setup"

# Skip validation
ansible-playbook -i inventory.ini site.yml --skip-tags "validation"
```

### 📦 Package Management

All OS-specific packages are centrally managed in `group_vars/all.yml`. You can easily customize packages for your environment:

#### Adding Packages
```yaml
# In group_vars/all.yml
system_packages:
  ubuntu:
    - bash-completion
    - jq
    - your-new-package    # Add here
  centos:
    - bash-completion
    - jq  
    - your-new-package    # Add here
```

#### Controlling Optional Components
```yaml
# In group_vars/all.yml
install_dev_tools: true          # Enable development tools
install_network_storage: false   # Disable NFS packages
install_time_sync: true          # Enable chrony
```

### 🛠 Supported Operating Systems

- **Ubuntu**: 18.04, 20.04, 22.04
- **Debian**: 10, 11
- **CentOS**: 7, 8, Stream
- **RHEL**: 7, 8, 9
- **Rocky Linux**: 8, 9
- **AlmaLinux**: 8, 9

### 📋 Deployment Stages

1. **Validation** - OS compatibility and system requirements check
2. **System Setup** - Base system configuration and packages
3. **Kubernetes Setup** - Cluster initialization and worker joining
4. **Applications** - Additional services and applications

### 🔧 Configuration Files

- `group_vars/all.yml` - Central configuration for all variables and packages
- `inventory.ini` - Host definitions and groupings
- `site.yml` - Main playbook with optimized role execution

### 📝 Examples

#### Custom Package Configuration
```yaml
# Add monitoring tools
system_packages:
  ubuntu:
    - htop
    - iotop
    - netstat-nat
  centos:
    - htop
    - iotop
    - net-tools

# Enable development environment
install_dev_tools: true
dev_tools_packages:
  ubuntu:
    - git
    - build-essential
    - python3-pip
    - nodejs
  centos:
    - git
    - gcc
    - gcc-c++
    - python3-pip
    - nodejs
```

### 🎯 Advanced Usage

#### Environment-specific Deployments
```bash
# Production deployment (minimal packages)
ansible-playbook -i inventory.ini site.yml -e "install_dev_tools=false"

# Development deployment (all packages)
ansible-playbook -i inventory.ini site.yml -e "install_dev_tools=true"
```

#### Selective Role Execution
```bash
# Only system preparation
ansible-playbook -i inventory.ini site.yml --tags "system_setup"

# Only Kubernetes applications
ansible-playbook -i inventory.ini site.yml --tags "applications"
```