# Kubernetes Cluster Basic Installation with Ansible

Automated basic Kubernetes cluster deployment using Ansible.

## 📋 Table of Contents

- [Overview](#overview)
- [System Requirements](#system-requirements)
- [Supported Platforms](#supported-platforms)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Installation](#installation)
- [Post-Installation](#post-installation)
- [Troubleshooting](#troubleshooting)

## 🎯 Overview

This Ansible playbook automates the deployment of a basic Kubernetes cluster with:

- **Core Kubernetes**: Kubernetes 1.27.14 cluster installation
- **Container Runtime**: containerd configuration
- **Network Plugin**: Flannel CNI for pod networking
- **System Preparation**: OS packages, kernel modules, firewall configuration
- **Cross-Platform**: Ubuntu and RHEL/CentOS support

## 💻 System Requirements

### Minimum Hardware Requirements

| Component | Master Node | Worker Node |
|-----------|-------------|-------------|
| **CPU** | 2 cores | 2 cores |
| **Memory** | 4GB RAM | 2GB RAM |
| **Storage** | 50GB SSD | 30GB SSD |
| **Network** | 1Gbps | 1Gbps |

### Recommended Production Setup

| Component | Master Node | Worker Node |
|-----------|-------------|-------------|
| **CPU** | 4+ cores | 2+ cores |
| **Memory** | 8+ GB RAM | 4+ GB RAM |
| **Storage** | 100+ GB SSD | 50+ GB SSD |
| **Network** | 1Gbps+ | 1Gbps+ |

## 🐧 Supported Platforms

### Operating Systems
- **Ubuntu**: 20.04 LTS, 22.04 LTS
- **RHEL/CentOS**: 8.x, 9.x
- **Rocky Linux**: 8.x, 9.x

### Kubernetes Versions
- **Current**: 1.27.14 (default)
- **Supported**: 1.25.x - 1.28.x

## 🚀 Quick Start

### Prerequisites

1. **Control Node Setup** (where Ansible runs):
   ```bash
   # Install Ansible (Ubuntu/Debian)
   sudo apt update
   sudo apt install ansible python3-pip
   
   # Install Ansible (RHEL/CentOS)
   sudo yum install epel-release
   sudo yum install ansible python3-pip
   ```

2. **Target Nodes Preparation**:
   - Fresh OS installation (Ubuntu 20.04+ or RHEL 8+)
   - Root access or sudo user
   - Network connectivity between all nodes
   - SSH key-based authentication

### SSH Key Setup

1. **Generate SSH key pair** (on control node):
   ```bash
   ssh-keygen -t rsa -b 4096 -C "ansible@kubernetes"
   ```

2. **Copy public key to all target nodes**:
   ```bash
   ssh-copy-id root@<master-node-ip>
   ssh-copy-id root@<worker-node-ip>
   ```

3. **Test connectivity**:
   ```bash
   ssh root@<node-ip> "uptime"
   ```

### Project Structure

```
kubernetes-kubeadm/
├── group_vars/
│   └── all.yml                 # Global variables
├── inventory.ini               # Inventory file
├── roles/                      # Ansible roles
│   ├── common/                 # Base system setup
│   ├── install_kubernetes/     # K8s installation
│   ├── install_containerd/     # Container runtime
│   └── install_flannel/        # CNI plugin
├── site.yml                    # Main playbook
└── README.md                   # This file
```

## ⚙️ Configuration

### 1. Inventory Configuration

Edit `inventory.ini` to match your infrastructure:

```ini
[masters]
master1 ansible_host=192.168.1.10

[workers]
worker1 ansible_host=192.168.1.11
worker2 ansible_host=192.168.1.12

[installs]
master1 ansible_host=192.168.1.10

[all:vars]
ansible_user=root
ansible_ssh_private_key_file=~/.ssh/id_rsa
```

### 2. Global Variables Configuration

Edit `group_vars/all.yml` with your environment-specific values:

```yaml
# Basic Kubernetes Configuration
kubernetes_version: '1.27.14'
dns_domain: cluster.local
service_subnet: 10.96.0.0/12
pod_subnet: 10.244.0.0/16

# Container Runtime
containerd_version: "1.7.6"

# System Configuration
set_timezone: Asia/Seoul

# NTP/Time Synchronization
use_local_ntp: true                    # true: master1 as NTP server, false: external NTP
external_ntp_servers:                  # External NTP servers (fallback or primary)
  - "pool.ntp.org"
  - "time.google.com" 
cluster_network: "192.168.0.0/16"     # Network allowed to access local NTP server

# Cluster Configuration
allow_master_scheduling: false         # Set to true for single-node cluster
network_plugin: "flannel"              # CNI plugin

# High Availability (for multi-master setup)
master_ha: false
kube_vip_port: 6443
kube_vip_interface: ens18
# kube_vip_address: 192.168.1.100      # Uncomment for HA setup

# Package Repository URLs (modify for your environment)
repo_url:
  centos: "http://192.168.1.10:8080/repo/"
  ubuntu: "http://192.168.1.10:8080/repo/"

# Container Registry Settings
insecure_registries:                   # HTTP registries (no TLS)
  - "192.168.1.10:5000"               # Local registry
  # - "harbor.yourdomain.com"         # Harbor registry
```

### 3. Optional Settings

Customize cluster behavior:

```yaml
# Single-node cluster (allow master scheduling)
allow_master_scheduling: true

# High Availability (multi-master)
master_ha: true
kube_vip_address: 192.168.1.100
```

## 🚀 Installation

### Step 1: Clone and Configure

```bash
git clone <repository-url>
cd kubernetes-kubeadm

# Edit configuration files
vim inventory.ini
vim group_vars/all.yml
```

### Step 2: Test Connectivity

```bash
ansible all -i inventory.ini -m ping
```

### Step 3: Deploy Kubernetes Cluster

```bash
# Install basic Kubernetes cluster
ansible-playbook -i inventory.ini site.yml
```

### Available Tags (Optional)

| Tag | Components |
|-----|------------|
| `base` | System preparation |
| `system` | OS configuration |
| `packages` | Package installation |
| `container` | Container runtime |
| `kubernetes` | K8s cluster |
| `cluster` | K8s core installation |
| `networking` | CNI plugin |
| `scheduling` | Master node scheduling |
| `certificates` | Certificate extension |

### 🎯 Kubernetes-Only Installation

If you want to install only Kubernetes components (skip system preparation):

```bash
# Install only Kubernetes core + networking
ansible-playbook -i inventory.ini site.yml --tags "kubernetes,networking"

# Install only Kubernetes cluster (without networking)
ansible-playbook -i inventory.ini site.yml --tags cluster

# Install networking only (if cluster already exists)
ansible-playbook -i inventory.ini site.yml --tags networking

# Extend certificates to 10 years
ansible-playbook -i inventory.ini site.yml --tags certificates
```

### 🔄 Quick Reinstall After Reset

```bash
# Reset cluster completely
ansible-playbook -i inventory.ini reset_cluster.yml

# Reinstall only Kubernetes (fast)
ansible-playbook -i inventory.ini site.yml --tags "kubernetes,networking"
```

## 🔧 Post-Installation

### 1. Verify Cluster Status

```bash
# Check cluster nodes
kubectl get nodes -o wide

# Check system pods
kubectl get pods -A

# Check cluster info
kubectl cluster-info
```

### 2. Configure kubectl (on master node)

```bash
# Copy kubeconfig for regular user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 3. Deploy Sample Application

```bash
# Deploy nginx example
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=NodePort

# Check deployment
kubectl get pods
kubectl get services
```

### 4. Basic Cluster Operations

```bash
# Scale deployment
kubectl scale deployment nginx --replicas=3

# Check node resources
kubectl top nodes

# Check pod logs
kubectl logs deployment/nginx
```

## 🔍 Troubleshooting

### Common Issues

1. **Node NotReady Status**
   ```bash
   # Check kubelet logs
   sudo journalctl -u kubelet -f
   
   # Check CNI (Flannel)
   kubectl get pods -n kube-system | grep flannel
   ```

2. **Pod Stuck in Pending**
   ```bash
   # Describe pod to see events
   kubectl describe pod <pod-name>
   
   # Check node resources
   kubectl describe nodes
   ```

3. **Join Command Issues**
   ```bash
   # On master, regenerate join command
   kubeadm token create --print-join-command
   
   # Check if node already joined
   kubectl get nodes
   ```

4. **Network Issues**
   ```bash
   # Check Flannel pods
   kubectl get pods -n kube-system -l app=flannel
   
   # Check pod-to-pod communication
   kubectl exec -it <pod-name> -- ping <target-ip>
   ```

### Health Check Script

```bash
#!/bin/bash
echo "=== Basic Cluster Health Check ==="
echo "Cluster Info:"
kubectl cluster-info
echo -e "\nNodes:"
kubectl get nodes -o wide
echo -e "\nSystem Pods:"
kubectl get pods -n kube-system
echo -e "\nNetwork Plugin (Flannel):"
kubectl get pods -n kube-system -l app=flannel
```

### Required Ports

| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 6443 | TCP | All | Kubernetes API |
| 2379-2380 | TCP | Masters | etcd |
| 10250 | TCP | All | kubelet |
| 10251 | TCP | Masters | kube-scheduler |
| 10252 | TCP | Masters | kube-controller |
| 8472 | UDP | All | Flannel VXLAN |

---

## 📝 Next Steps

After basic cluster installation, you can:

1. **Install Kubernetes Dashboard**
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
   ```

2. **Install Metrics Server**
   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
   ```

3. **Deploy Applications**
   - Use `kubectl create deployment`
   - Apply YAML manifests
   - Use Helm charts

## 📚 Additional Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Ansible Documentation](https://docs.ansible.com/)
- [Flannel Documentation](https://github.com/flannel-io/flannel)