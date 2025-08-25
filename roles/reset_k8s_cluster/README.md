# Kubernetes Cluster Reset Role

This role completely resets a Kubernetes cluster created with kubeadm, removing all configuration files, data, and optionally packages.

## Description

This role performs a comprehensive cleanup of a Kubernetes cluster including:
- Running `kubeadm reset`
- Removing all Kubernetes configuration and data directories
- Cleaning up CNI configurations and network interfaces
- Optionally removing container images and packages
- Cleaning up iptables rules (if specified)

## ⚠️ WARNING

**This is a destructive operation that will:**
- Stop all running pods and services
- Remove all Kubernetes cluster data
- Delete etcd data (on master nodes)
- Remove user kubectl configurations
- Optionally remove container images and packages

**Use with extreme caution!**

## Features

- ✅ Complete kubeadm reset with confirmation prompt
- ✅ Comprehensive cleanup of Kubernetes files and directories
- ✅ CNI network interface cleanup (Flannel, Calico, etc.)
- ✅ Optional container image removal
- ✅ Optional package removal (kubelet, kubeadm, kubectl)
- ✅ Optional iptables rules cleanup
- ✅ Support for both Docker and containerd runtimes
- ✅ Configurable cleanup options

## Requirements

- Ansible 2.9 or higher
- Root or sudo access on target nodes
- Kubernetes cluster installed with kubeadm

## Role Variables

Available variables in `vars/main.yml`:

```yaml
# Container runtime
container_runtime: "containerd"  # or "docker"

# Safety settings
require_reset_confirmation: true  # Prompt for confirmation

# Cleanup options
remove_container_images: false   # Remove all container images
remove_k8s_packages: false      # Remove k8s packages
remove_container_runtime: false  # Remove containerd/docker
reset_iptables: false           # Reset iptables (dangerous!)

# Swap settings
enable_swap_after_reset: false  # Re-enable swap after reset
```

## Dependencies

None

## Example Playbooks

### 1. Safe Reset (with confirmation)

```yaml
- name: Reset Kubernetes Cluster
  hosts: all
  become: yes
  roles:
    - role: reset_k8s_cluster
```

### 2. Automated Reset (no confirmation)

```yaml
- name: Automated Kubernetes Reset
  hosts: all
  become: yes
  roles:
    - role: reset_k8s_cluster
      vars:
        require_reset_confirmation: false
```

### 3. Complete Cleanup (remove everything)

```yaml
- name: Complete Kubernetes Cleanup
  hosts: all
  become: yes
  roles:
    - role: reset_k8s_cluster
      vars:
        require_reset_confirmation: false
        remove_container_images: true
        remove_k8s_packages: true
        remove_container_runtime: true
        reset_iptables: true
```

### 4. Reset specific groups

```yaml
- name: Reset Masters Only
  hosts: masters
  become: yes
  roles:
    - reset_k8s_cluster

- name: Reset Workers Only
  hosts: workers
  become: yes
  roles:
    - reset_k8s_cluster
```

## Usage

### Step 1: Run the reset playbook

```bash
# Safe reset with confirmation
ansible-playbook -i inventory.ini reset_cluster.yml

# Automated reset without confirmation
ansible-playbook -i inventory.ini reset_cluster.yml -e "require_reset_confirmation=false"

# Complete cleanup
ansible-playbook -i inventory.ini reset_cluster.yml -e "remove_container_images=true remove_k8s_packages=true"
```

### Step 2: Reboot (recommended)

```bash
ansible all -i inventory.ini -m reboot
```

### Step 3: Reinstall cluster

```bash
ansible-playbook -i inventory.ini site.yml
```

## What Gets Removed

### Always Removed:
- `/etc/kubernetes/` - All Kubernetes configuration
- `/var/lib/kubelet/` - kubelet data
- `/var/lib/kubeadm/` - kubeadm configuration
- `/var/lib/etcd/` - etcd data (masters only)
- `/etc/cni/net.d/` - CNI configuration
- `~/.kube/` - User kubectl config
- CNI network interfaces (flannel, calico, etc.)

### Optionally Removed:
- Container images (if `remove_container_images: true`)
- Kubernetes packages (if `remove_k8s_packages: true`)
- Container runtime (if `remove_container_runtime: true`)
- iptables rules (if `reset_iptables: true`)

## Safety Features

- **Confirmation prompt** - Requires user confirmation by default
- **Service checks** - Checks if kubeadm exists before running
- **Graceful failures** - Most operations use `failed_when: false`
- **Detailed logging** - Shows what is being removed

## Tags

Use tags to run specific operations:

### Reset Operations:
```bash
# Run only the reset without cleanup
ansible-playbook -i inventory.ini reset_cluster.yml --tags reset

# Run only file cleanup
ansible-playbook -i inventory.ini reset_cluster.yml --tags cleanup
```

### Kubernetes Installation Tags:
After resetting, you can install only specific components using tags:

```bash
# Install only Kubernetes core components (skip system prep)
ansible-playbook -i inventory.ini site.yml --tags kubernetes

# Install only Kubernetes cluster (kubeadm, kubelet, kubectl)
ansible-playbook -i inventory.ini site.yml --tags cluster

# Install only networking (Flannel)
ansible-playbook -i inventory.ini site.yml --tags networking

# Install only certificate extension
ansible-playbook -i inventory.ini site.yml --tags certificates

# Combined: Install Kubernetes + networking
ansible-playbook -i inventory.ini site.yml --tags "kubernetes,networking"

# Full Kubernetes setup (cluster + networking + certificates)
ansible-playbook -i inventory.ini site.yml --tags "cluster,networking,certificates"
```

### Common Tag Combinations:
```bash
# Quick K8s reinstall after reset (skip system packages)
ansible-playbook -i inventory.ini reset_cluster.yml && \
ansible-playbook -i inventory.ini site.yml --tags "kubernetes,networking"

# Complete reinstall (everything)
ansible-playbook -i inventory.ini reset_cluster.yml && \
ansible-playbook -i inventory.ini site.yml

# Install only K8s core without networking
ansible-playbook -i inventory.ini site.yml --tags cluster
```

## Recovery

If you need to recover after an accidental reset:
1. Restore from backups (if available)
2. Reinstall the cluster using the installation playbook
3. Restore application data from backups

## Author

Generated for comprehensive Kubernetes cluster cleanup and reset operations.