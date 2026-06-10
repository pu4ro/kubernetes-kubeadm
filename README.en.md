# Kubernetes Cluster Automation (Ansible)

> **Language / 언어:** [한국어](./README.md) · [English](./README.en.md)

Ansible-based Kubernetes cluster deployment toolkit. Supports Flannel/Cilium CNI, HA, OIDC authentication, registry mirror, GPU, offline installation, and other production-grade operational features.

## 📋 Table of Contents

- [Overview](#overview)
- [📂 Documentation Map](#-documentation-map)
- [Compatibility Matrix](#compatibility-matrix)
- [System Requirements](#system-requirements)
- [Quick Start](#quick-start) (Single / Offline / HA)
- [CNI Selection (Flannel vs Cilium)](#cni-selection-flannel-vs-cilium)
- [Configuration (group_vars/all.yml)](#configuration-group_varsallyml)
- [New Feature Sections](#new-feature-sections)
  - [OIDC Authentication](#oidc-authentication)
  - [Registry Mirror](#registry-mirror)
  - [Custom CA Certificates](#custom-ca-certificates)
  - [Dedicated Containerd Disk](#dedicated-containerd-disk)
  - [GPU Auto-configuration](#gpu-auto-configuration)
  - [Cluster Validation (`validation.yml`)](#cluster-validation-validationyml)
- [Makefile Commands](#makefile-commands)
- [Ansible Tags](#ansible-tags)
- [Runbook Links](#runbook-links)
- [Troubleshooting](#troubleshooting)
- [HA Cluster IP Change](#ha-cluster-ip-change)
- [Additional Resources](#additional-resources)

## Overview

This Ansible playbook automatically deploys a Kubernetes cluster including:

- **Kubernetes core**: Supports 1.27.x – 1.34.x (kubeadm v1beta3 ↔ v1beta4 auto-branching)
- **Container runtime**: containerd 1.7.x – 2.2.x (config v2 ↔ v3 auto-detection)
- **CNI plugin**: Choose Flannel or Cilium, **with offline Cilium install support**
- **System prep**: OS packages, kernel modules, sysctl, NTP
- **Registry auth**: containerd-native (`/etc/containerd/certs.d`) + nerdctl login
- **Registry mirror**: Auto-redirect external registries (docker.io, quay.io, etc.) to internal mirror
- **OIDC auth**: kube-apiserver + external IdP (Keycloak, etc.)
- **High availability**: kube-vip or domain-based HA, multi-master
- **GPU support**: Auto NVIDIA driver install, containerd runtime config, automatic node labeling
- **Custom CA certs**: Install into system trust store (3 input modes)
- **Dedicated disk**: Isolate containerd data on a separate disk (optional)
- **Certificate management**: Standard 1-year or 10-year auto-extension
- **Cluster validation**: 5-step automated health check (`make validate`)
- **Cross-platform**: Ubuntu 20.04+, RHEL/Rocky/CentOS 8+
- **Offline installation**: Internal APT/YUM mirrors, pre-staged Cilium

## 📂 Documentation Map

| Purpose | Document |
|---|---|
| **Quick start** | [Quick Start](#quick-start) section of this README |
| **All variables, detailed** | [`group_vars/all.yml.example`](./group_vars/all.yml.example) (10-line bilingual annotation per variable) |
| **Operational scenarios (install/IP change/incident response)** | [`runbooks/`](./runbooks/README.en.md) ([Index](./runbooks/README.en.md)) |
| **Worker addition details** | [`runbooks/02-add-worker.en.md`](./runbooks/02-add-worker.en.md) (legacy: [`ADD-WORKER-GUIDE.md`](./ADD-WORKER-GUIDE.md)) |
| **Containerd data dir customization** | [`CONTAINERD-CUSTOM-PATH.md`](./CONTAINERD-CUSTOM-PATH.md) (legacy detail) |
| **Detailed Makefile target reference** | [`MAKEFILE-GUIDE.md`](./MAKEFILE-GUIDE.md) (legacy detail) |
| **Legacy install guide** | [`k8s-setup-README.md`](./k8s-setup-README.md) (legacy — current procedure: [`runbooks/01-day0-install.en.md`](./runbooks/01-day0-install.en.md)) |

## Compatibility Matrix

| Component | Supported range | Tested default | Notes |
|---|---|---|---|
| **Kubernetes** | 1.27.x – 1.34.x | `1.34.1` | ≤1.30 → kubeadm v1beta3, ≥1.31 → v1beta4 (auto-branch) |
| **containerd** | 1.7.x – 2.2.x | `2.2.0` | <2.2 → config v2, ≥2.2 → config v3 (auto-detect) |
| **CNI** | Flannel, Cilium 1.15.x | `flannel` | Selected via `network_plugin` |
| **OS (Ubuntu)** | 20.04 LTS, 22.04 LTS, 24.04 LTS | 22.04 | |
| **OS (RHEL/Rocky/CentOS)** | 8.x, 9.x | 8.x | |
| **kube-vip** | 0.7.x+ | latest | When using HA + VIP |
| **OIDC IdP** | Standard OIDC compliant | Keycloak 23+ | Optional |

> **Changing the version**: Set `kubernetes_version: "1.27.14"` or `containerd_version: "1.7.6"` etc. in `group_vars/all.yml`. All K8s 1.27.x – 1.34.x versions work with the same playbook.

## System Requirements

### Minimum Hardware

| Component | Master | Worker |
|-----------|--------|--------|
| **CPU** | 2 cores | 2 cores |
| **Memory** | 4GB RAM | 2GB RAM |
| **Storage** | 50GB SSD | 30GB SSD |
| **Network** | 1Gbps | 1Gbps |

### Recommended Production

| Component | Master | Worker |
|-----------|--------|--------|
| **CPU** | 4+ cores | 2+ cores |
| **Memory** | 8+ GB RAM | 4+ GB RAM |
| **Storage** | 100+ GB SSD | 50+ GB SSD |
| **Network** | 1Gbps+ | 1Gbps+ |

### Required Ports

| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 6443 | TCP | All | Kubernetes API |
| 2379-2380 | TCP | Master | etcd |
| 10250 | TCP | All | kubelet |
| 10257 | TCP | Master | kube-controller-manager (1.20+) |
| 10259 | TCP | Master | kube-scheduler (1.20+) |
| 8472 | UDP | All | Flannel VXLAN (CNI=flannel) |
| 4240 | TCP | All | Cilium health (CNI=cilium) |
| 4244 | TCP | All | Cilium Hubble (CNI=cilium, optional) |
| 8443 | TCP | Master | kube-vip (when using HA) |

## Quick Start

### Prerequisites

**Control node** (where Ansible runs):

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y ansible python3-pip sshpass

# RHEL/CentOS
sudo yum install -y epel-release
sudo yum install -y ansible python3-pip sshpass
```

**SSH key setup**:

```bash
ssh-keygen -t rsa -b 4096 -C "ansible@kubernetes"
ssh-copy-id root@<master-node-ip>
ssh-copy-id root@<worker-node-ip>
ssh root@<node-ip> "uptime"   # connectivity test
```

**Clone repository + config**:

```bash
git clone <repository-url>
cd kubernetes-kubeadm

# 1. Edit inventory
vim inventory.ini

# 2. ⚠️ Always start from .example (the file with real credentials is gitignored)
cp group_vars/all.yml.example group_vars/all.yml
vim group_vars/all.yml
```

> **First-time user note**: `group_vars/all.yml.example` contains all 110 variables with detailed Korean + English comments. Read top-to-bottom and edit only what your environment needs.

### Scenario A — Single Master (simplest, ~15 min)

For when you want a cluster up as fast as possible.

#### 1. Pre-flight check
```bash
make ping
# Expected output: all hosts SUCCESS / pong
```
> If it fails: check SSH key, ansible_host/ansible_user in inventory.ini.

#### 2. Edit variables (`group_vars/all.yml`)
```yaml
master_ha: false                      # single master
network_plugin: "flannel"             # or "cilium"
allow_master_scheduling: true         # true for single-node
enable_domain_communication: false    # not needed for single master
docker_login_required: false          # false if no private registry
enable_registry_mirror: false         # use internet directly
```

#### 3. Install
```bash
make install
# Or stepped: make install-step1 && make install-step2 && make install-step3
# Duration: ~15 min (varies by network and node spec)
```
> Expected output (end):
> ```
> PLAY RECAP *********************************************************************
> master1 : ok=42  changed=18  unreachable=0  failed=0  skipped=5
> ```

#### 4. Validate
```bash
make validate
# 5-step validation: nodes Ready / kube-system pods / DNS / Pod-to-Pod / external
# Expected output (end):
#   "  Cluster Validation: ALL CHECKS PASSED  "
```
> If it fails: see [`runbooks/05-incident-response.en.md`](./runbooks/05-incident-response.en.md).

### Scenario B — Offline Install (air-gapped, ~30 min)

For isolated environments. Internal mirror servers must be pre-configured.

#### Pre-staging (on a host with internet)
- Ubuntu APT / RHEL YUM mirror (host via internal Apache/Nginx)
- Pre-download Cilium CLI: `cilium-linux-amd64.tar.gz` → `roles/install_cilium/files/`
- Container images: push to internal Harbor/Registry (`harbor.example.com/external-hub/...`)

#### Edit variables (`group_vars/all.yml`)
```yaml
# Offline K8s + containerd repos
enable_official_k8s_repo: false
enable_official_containerd_repo: false

# Ubuntu
enable_ubuntu_repo: true
ubuntu_repo_url: "http://mirror.example.com/ubuntu-repo"

# RHEL
enable_rhel_repos: true
rhel_repos:
  - name: "rhel-iso-repo"
    id: "rhel-iso-repo"
    url: "http://mirror.example.com/rhel-repo"
    type: "baseos_appstream"
    enabled: 1
    gpgcheck: 0
    priority: 1

# K8s component images via internal mirror
enable_custom_image_repository: true
k8s_image_repository: "harbor.example.com/external-hub/kubernetes"
coredns_image_repository: "harbor.example.com/external-hub/kubernetes/coredns"
pause_image: "harbor.example.com/external-hub/kubernetes/pause:3.10"

# Cilium (if used) offline
network_plugin: "cilium"
cilium_offline_install: true
cilium_image_repository: "harbor.example.com/cilium"

# External registry mirror (optional)
enable_registry_mirror: true
registry_mirror_host: "harbor.example.com"
registry_mirror_user: "<your-username>"
registry_mirror_password: "<your-password>"

# Override the validation external URL to an internal host
# (validation.yml's external check uses google.com by default — fails in air-gapped)
```

> ⚠️ The `validation.yml` external check defaults to `http://google.com`. In air-gapped environments, override `validation_external_url` (in `roles/validate_cluster/defaults/main.yml`) to an internal host. Or use `make check-cluster` instead of `make validate`.

#### Install + validate
```bash
make install
make check-cluster   # validate's external check may fail in air-gapped env
```

### Scenario C — HA 3-Master (~45 min)

Production setup. Choose kube-vip or domain-based HA.

#### Option 1: kube-vip (VIP)
```yaml
# group_vars/all.yml
master_ha: true
kube_vip_address: 192.168.1.30        # unused VIP (same subnet as masters)
kube_vip_port: 6443
kube_vip_interface: ens18              # actual NIC name! verify via `ip link show`
```

#### Option 2: Domain-based (external LB or single IP)
```yaml
# group_vars/all.yml
master_ha: true
enable_domain_communication: true
domain_suffix: "k8s.local"
api_domain: "k8s-api.internal"
# kube_vip_address is NOT defined

# DNS or /etc/hosts must resolve api_domain to first master (or LB) IP
custom_hosts:
  "k8s-api.internal": "192.168.1.31"  # or external LB IP
```

```ini
# inventory.ini
[masters]
master1 ansible_host=192.168.1.31
master2 ansible_host=192.168.1.32
master3 ansible_host=192.168.1.33

[workers]
worker1 ansible_host=192.168.1.41
worker2 ansible_host=192.168.1.42

[installs]
master1 ansible_host=192.168.1.31

[all:vars]
ansible_user=root
ansible_become=true
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

#### Install + validate
```bash
make install               # site.yml installs masters serial:1 (avoids etcd race)
make check-etcd-health     # HA: confirm 3/3 healthy
make check-etcd-members
make validate
```

> Detailed HA install procedure: [`runbooks/01-day0-install.en.md`](./runbooks/01-day0-install.en.md) (Scenario C).

## CNI Selection (Flannel vs Cilium)

Selected via `network_plugin`:

```yaml
# group_vars/all.yml
network_plugin: "flannel"   # or "cilium"
```

### Selection guide

| Requirement | Recommendation |
|---|---|
| **Simple L3 routing, minimal resources** | Flannel |
| **NetworkPolicy enforcement** | Cilium |
| **eBPF data plane, observability (Hubble)** | Cilium |
| **Replace kube-proxy (with eBPF)** | Cilium (`cilium_kube_proxy_replacement: strict`) |
| **WireGuard encryption** | Cilium (`cilium_encryption_enabled: true`) |
| **Simple PoC, fast start** | Flannel |

### Flannel config

```yaml
network_plugin: "flannel"
pod_subnet: 10.244.0.0/16   # matches Flannel default
```

### Cilium config (online)

```yaml
network_plugin: "cilium"
cilium_version: "1.15.5"
cilium_cli_version: "v0.16.8"
cilium_arch: "amd64"        # or "arm64"
cilium_offline_install: false
```

### Cilium offline install

```yaml
network_plugin: "cilium"
cilium_offline_install: true                       # skip GitHub download
cilium_image_repository: "harbor.example.com/cilium"  # internal mirror
```

Also requires the pre-downloaded CLI binary at `roles/install_cilium/files/cilium-linux-amd64.tar.gz`:

```bash
# Pre-download (on a host with internet)
curl -LO https://github.com/cilium/cilium-cli/releases/download/v0.16.8/cilium-linux-amd64.tar.gz
mv cilium-linux-amd64.tar.gz roles/install_cilium/files/
```

## Configuration (group_vars/all.yml)

> **Detailed variable documentation** lives in [`group_vars/all.yml.example`](./group_vars/all.yml.example) (110 variables, 10-line bilingual annotation each). This section summarizes frequently-edited variables.

### Quick edit guide

```yaml
# ── 1. Kubernetes core ──
kubernetes_version: "1.34.1"          # supports 1.27.x ~ 1.34.x
dns_domain: cluster.local
service_subnet: 10.96.0.0/12
pod_subnet: 10.244.0.0/16

# ── 2. HA / domain ──
master_ha: true                        # multi-master
# kube_vip_address: 192.168.1.30      # VIP method
enable_domain_communication: true     # domain method
api_domain: "k8s-api.internal"

# ── 3. Container runtime ──
containerd_version: "2.2.0"           # 1.7.x ~ 2.2.x
containerd_data_base_dir: ""          # empty = /var/lib/containerd

# ── 4. CNI ──
network_plugin: "flannel"             # or "cilium"

# ── 5. System ──
set_timezone: Asia/Seoul
set_hostname_from_inventory: true
parallel_execution:
  system_preparation: 0               # 0=parallel, 1=serial
  package_installation: 0
  kubernetes_installation: 0

# ── 6. Packages/repos ──
enable_ubuntu_repo: false
enable_rhel_repos: false

# ── 7. Auth/security ──
docker_login_required: false
docker_registries: []
enable_oidc_apiserver: false
enable_pod_node_selector: false
enable_ca_certificates: false

# ── 8. GPU ──
enable_nvidia_driver_install: false
enable_nvidia_containerd_config: false
enable_gpu_node_labels: true

# ── 9. Registry mirror ──
enable_registry_mirror: false

# ── 10. Certificates ──
extend_k8s_certificates: true         # 10-year extend
allow_master_scheduling: true         # true for single-node

# ── 11. Disk ──
enable_containerd_disk: false         # ⚠️ true formats the disk
```

## New Feature Sections

### OIDC Authentication

Add OIDC authentication to kube-apiserver to integrate with external IdPs like Keycloak. The `configure_oidc_apiserver` role auto-backs up `/etc/kubernetes/manifests/kube-apiserver.yaml` before modifying.

```yaml
enable_oidc_apiserver: true
domain_host: "example.com"                                              # Base domain for OIDC issuer
oidc_client_id: "kubernetes"
oidc_username_claim: "preferred_username"
oidc_groups_claim: "client_roles"
oidc_issuer_url: "https://keycloak.{{ domain_host }}/realms/example"
# oidc_ca_file: "/etc/kubernetes/pki/idp-ca.crt"                         # for self-signed IdP
```

```bash
make tag-oidc-apiserver           # Apply OIDC only (add to existing cluster)
```

**After applying**:
- Backup file: `/etc/kubernetes/kube-apiserver.yaml.backup-<epoch>`
- API server auto-restart (Pod recreation ~30s)
- Verify: `kubectl --kubeconfig /etc/kubernetes/admin.conf -n kube-system get pod -l component=kube-apiserver -o yaml | grep oidc-issuer-url`

**Rollback**:
```bash
ssh master1
sudo cp /etc/kubernetes/kube-apiserver.yaml.backup-<epoch> /etc/kubernetes/manifests/kube-apiserver.yaml
# kubelet auto-restarts the Pod
```

For detailed operations: [`runbooks/05-incident-response.en.md § OIDC auth failure`](./runbooks/05-incident-response.en.md).

### Registry Mirror

containerd auto-redirects external registry pulls (docker.io, quay.io, registry.k8s.io, etc.) to an internal mirror. The `configure_registry_mirror` role auto-generates `/etc/containerd/certs.d/<host>/hosts.toml`.

```yaml
enable_registry_mirror: true
registry_mirror_host: "harbor.example.com"
registry_mirror_user: "<your-username>"
registry_mirror_password: "<your-password>"
registry_mirror_path_prefix: ""

registry_mirror_mappings:
  "docker.io": "docker-io"
  "quay.io": "quay-io"
  "ghcr.io": "ghcr-io"
  "nvcr.io": "nvcr-io"
  "registry.k8s.io": "registry-k8s-io"
  # add more
```

```bash
make tag-registry-mirror      # Add mirror config to existing cluster
```

**Effect**:
- All external registry pulls redirect to `harbor.example.com/<mapped-name>/<image>`
- containerd auto-restart
- `docker.io` is special-cased (uses `registry-1.docker.io`)

**Verify**:
```bash
ansible all -i inventory.ini -m shell -a "ls /etc/containerd/certs.d/"
ansible all -i inventory.ini -m shell -a "cat /etc/containerd/certs.d/docker.io/hosts.toml"
```

### Custom CA Certificates

Install self-signed Harbor or internal PKI certs into the system trust store. 3 input modes:

```yaml
enable_ca_certificates: true
ca_certificates:
  # Mode 1: inline PEM content
  - name: "internal-ca"
    content: |
      -----BEGIN CERTIFICATE-----
      MIIDxTCCAq2g...
      -----END CERTIFICATE-----

  # Mode 2: download from URL
  - name: "harbor-ca"
    url: "https://harbor.example.com/ca.crt"

  # Mode 3: copy from local file
  - name: "registry-ca"
    path: "/root/certs/my-ca.crt"
```

```bash
make tag-docker-credentials   # Install CA + docker-credentials together
```

OS-specific install paths:
- **Debian/Ubuntu**: `/usr/local/share/ca-certificates/<name>.crt` + `update-ca-certificates`
- **RHEL/CentOS**: `/etc/pki/ca-trust/source/anchors/<name>.crt` + `update-ca-trust extract`

### Dedicated Containerd Disk

> ⚠️ **Data loss warning**: Setting `enable_containerd_disk: true` will **format** the specified disk (only when no existing filesystem; the role uses `force: no` as a safeguard). Wrong device path = data loss possible. **Always double-check the device path.**

```yaml
enable_containerd_disk: true
containerd_disk_device: "/dev/sdb"             # ⚠️ empty disk
containerd_disk_fstype: "xfs"                  # "xfs" | "ext4"
containerd_disk_mount_point: "/var/lib/containerd"
containerd_disk_mount_options: "defaults,noatime"
```

```bash
make tag-setup-containerd-disk    # Run before containerd install (recommended)
# Or check first with dry-run
make dry-run
```

Role behavior (13 phases):
1. Verify device exists
2. Check existing mount/blkid
3. **Format only if no existing FS** (`force: no`)
4. Add fstab entry by UUID (persistent mount)
5. Restart containerd

### GPU Auto-configuration

Three independent stages — combine as needed.

```yaml
# 1. Auto NVIDIA driver install (.run file)
enable_nvidia_driver_install: true
nvidia_driver_version: "570.124.06"
nvidia_driver_download_url: "http://mirror.example.com/nvidia-drivers"

# 2. Toolkit path fix (after .run install, if needed)
enable_fix_nvidia_toolkit_path: true

# 3. Add NVIDIA runtime to containerd config
enable_nvidia_containerd_config: true

# 4. Auto-label GPU nodes (gpu=on)
enable_gpu_node_labels: true   # default true
```

```bash
make configure-gpu-full         # Run all 4 stages at once
make check-nvidia-gpu           # Verify GPU detection (lspci)
make check-nvidia-driver        # Verify driver install
```

Example GPU workload scheduling:
```yaml
spec:
  nodeSelector:
    gpu: "on"
  containers:
  - name: app
    image: nvidia/cuda:12.0-base
    resources:
      limits:
        nvidia.com/gpu: 1
```

### Cluster Validation (`validation.yml`)

Comprehensive cluster health check, post-install or post-change:

```bash
make validate
```

**5-step validation**:
1. **Node Status** — verify all nodes `Ready`
2. **System Pods** — verify all `kube-system` pods Running/Completed
3. **DNS Resolution** — busybox pod runs `nslookup kubernetes.default`
4. **Pod-to-Pod Communication** — verify HTTP 200 between two nginx pods
5. **External Connectivity** — pod accesses `http://google.com` (or `validation_external_url`)

**Air-gapped note**: Override `validation_external_url` (defined in `roles/validate_cluster/defaults/main.yml`):
```yaml
# Add to group_vars/all.yml
validation_external_url: "http://harbor.example.com/health"
```

Success output:
```
=========================================
  Cluster Validation: ALL CHECKS PASSED
=========================================
  - Node Status:           OK
  - System Pods:           OK
  - DNS Resolution:        OK
  - Pod-to-Pod Comms:      OK
  - External Connectivity: OK
=========================================
```

If it fails: see [`runbooks/05-incident-response.en.md`](./runbooks/05-incident-response.en.md).

## Makefile Commands

Full target list: `make help` or [`MAKEFILE-GUIDE.md`](./MAKEFILE-GUIDE.md). Most-used ones below.

### General

| Command | Description | Frequency |
|---|---|---|
| `make help` | Full target list | Often |
| `make ping` | SSH connectivity test for all hosts | Often |
| `make check-cluster` | Node + Pod status | Often |
| `make validate` | 5-step cluster validation | Often |
| `make check-versions` | Show installed versions | Sometimes |
| `make show-variables-example` | Print safe variable file (no secrets) | Sometimes |

### Install

| Command | Description |
|---|---|
| `make install` | Full cluster install (entire `site.yml`) |
| `make install-step1` | Phase 1: system prep (sysctl + packages + containerd) |
| `make install-step2` | Phase 2: K8s install (kubeadm) |
| `make install-step3` | Phase 3: CNI plugin |
| `make install-all` | step1 → step2 → step3 sequentially |
| `make install-minimal` | Minimal config |
| `make install-production` | Production-recommended config |

### Tag-based partial apply

| Command | Target | Common use |
|---|---|---|
| `make tag-sysctl` | Kernel params only | Sync new node |
| `make tag-packages` | OS packages only | Package update |
| `make tag-container` | containerd only | Runtime reconfig |
| `make tag-docker-credentials` | Registry auth + CA | Credential rotation |
| `make tag-kubernetes` | K8s components only | Cert/node reconfig |
| `make tag-networking` | Reinstall CNI | CNI change |
| `make tag-certs` | 10-year cert extension | Cert renewal |
| `make tag-coredns` | CoreDNS hosts | hosts sync |
| `make tag-oidc-apiserver` | Add OIDC config | Auth policy change |
| `make tag-registry-mirror` | Registry mirror | Mirror addition |
| `make tag-label-gpu-nodes` | GPU node labels | Add GPU |

### Worker management

```bash
make check-workers              # Worker status
make add-workers                # Manual worker add
make check-and-add-workers      # Auto-detect from inventory + add
make get-join-command           # Print fresh join command
```

### Per-host / command exec

```bash
make limit-master               # Masters only
make limit-master1              # master1 only
make limit-workers              # Workers only

make cmd-all CMD="uptime"
make cmd-masters CMD="kubectl get nodes"
make cmd-workers CMD="free -h"
make cmd-host HOST="master1" CMD="systemctl status kubelet"
```

### IP change / certificates

```bash
# Single master IP change
make update-ip OLD_IP=192.168.1.41 NEW_IP=192.168.1.100 HOST=master1
make update-ip-with-certs OLD_IP=... NEW_IP=... HOST=...   # with cert SAN regen

# HA cluster (one master at a time)
make update-ha-ip OLD_IP=... NEW_IP=... HOST=master1
make check-etcd-health
make check-etcd-members
```

### Reset / cleanup

```bash
make reset                      # Full cluster reset (⚠️ data loss)
make reset-workers              # Workers only
make reset-and-reboot           # Reset then reboot
make reset-rook-ceph            # Pre-cleanup rook-ceph
```

### Local registry / NFS

```bash
make registry-init / registry-start / registry-stop / registry-status
make nfs-init / nfs-install / nfs-start / nfs-status / nfs-show-exports
```

### Internal repos (offline)

```bash
make ubuntu-repo-init / ubuntu-repo-setup / ubuntu-repo-status
make rhel-repo-init-iso / rhel-repo-setup-directory
make apache-repo-install / apache-repo-status
make httpd-repo-install-iso / httpd-repo-status
```

## Ansible Tags

### Main tags by phase

| Phase | Tag | Target |
|---|---|---|
| 1. System prep | `base`, `sysctl`, `packages`, `set-hostname`, `etc-hosts` | All nodes |
| 1. Container | `container`, `containerd-config`, `containerd-binary-install`, `registry-mirror`, `docker-credentials`, `nerdctl-login`, `ca-certificates` | All nodes |
| 1. Repos | `rhel-repo`, `ubuntu-repo`, `k8s-official-repo` | All nodes |
| 1. GPU | `nvidia`, `install-nvidia-driver`, `fix-nvidia-toolkit-path`, `gpu` | GPU nodes |
| 1. Disk | `setup-containerd-disk` | All nodes (optional) |
| 2. K8s | `kubernetes`, `cluster` | Master + Worker |
| 3. Network | `networking`, `flannel`, `cilium` | Master |
| 4. Scheduling | `scheduling`, `label-gpu-nodes` | Master |
| 5. Certs | `certificates`, `k8s-certs` | Master |
| 6. CoreDNS | `coredns-hosts` | Master |
| 7. OIDC | `oidc-apiserver` | Master |

### Usage examples

```bash
# Sysctl only
ansible-playbook -i inventory.ini site.yml --tags sysctl

# System prep (excluding K8s)
ansible-playbook -i inventory.ini site.yml --tags sysctl,packages,container

# Reinstall K8s only
ansible-playbook -i inventory.ini site.yml --tags kubernetes,networking

# Cert extension
ansible-playbook -i inventory.ini site.yml --tags k8s-certs

# Combined tags
ansible-playbook -i inventory.ini site.yml --tags "sysctl,container,kubernetes"

# Limit to specific host
ansible-playbook -i inventory.ini site.yml --tags kubernetes --limit master1
```

Full tag list: `make list-tags`

## Runbook Links

Per-scenario SOPs for operators are in [`runbooks/`](./runbooks/README.en.md):

| # | Runbook | Risk | Duration |
|---|---|---|---|
| 00 | [Prerequisites](./runbooks/00-prerequisites.en.md) | Low | 30–60 min |
| 01 | [Day-0 Cluster Install](./runbooks/01-day0-install.en.md) (Online / Offline / HA) | Medium | 30–90 min |
| 02 | [Add/Remove Worker](./runbooks/02-add-worker.en.md) | Medium | 15–30 min |
| 03 | [Cert Renewal](./runbooks/03-cert-renewal.en.md) (10y extend / 1y renew) | High | 15–30 min |
| 04 | [Node IP Change](./runbooks/04-node-ip-change.en.md) (single / HA) | High | 30–90 min |
| 05 | [Incident Response](./runbooks/05-incident-response.en.md) (NotReady / etcd / CNI / registry) | varies | immediate |
| 06 | [Cluster Reset/Redeploy](./runbooks/06-cluster-reset.en.md) | High | 15–60 min |

## Troubleshooting

### Node NotReady

#### Symptom
```bash
kubectl get nodes
# NAME      STATUS     ROLES           AGE   VERSION
# master1   NotReady   control-plane   10m   v1.34.1
```

#### Diagnose
```bash
# kubelet logs
ssh master1
sudo journalctl -u kubelet -f

# CNI status (Flannel)
kubectl get pods -n kube-flannel
kubectl logs -n kube-flannel -l app=flannel

# CNI status (Cilium)
cilium status
cilium connectivity test
```

#### Common causes
- **Swap is on**: `swapoff -a` (auto-handled but may revert after reboot)
- **containerd not running**: `systemctl status containerd`
- **CNI image pull failure**: see next section

Detailed procedure: [`runbooks/05-incident-response.en.md § Node NotReady`](./runbooks/05-incident-response.en.md).

### Image pull failure (`ErrImagePull` / `ImagePullBackOff`)

#### Diagnose
```bash
# Check events
kubectl describe pod <pod>

# Test pull directly on the node
ssh worker1
sudo nerdctl pull harbor.example.com/library/nginx:latest

# Verify containerd auth config
sudo cat /etc/containerd/config.toml | grep -A 5 registry
sudo ls /etc/containerd/certs.d/
```

#### Resolution
- **Auth error**: verify `docker_registries` in `group_vars/all.yml` → re-run `make tag-docker-credentials`
- **Untrusted CA**: set `enable_ca_certificates: true` + add `ca_certificates` → `make tag-ca-certificates`
- **Mirror config error**: re-run `make tag-registry-mirror`, inspect `/etc/containerd/certs.d/`

### Worker join failure

```bash
make get-join-command
# or
ssh master1
sudo kubeadm token create --print-join-command
```

### etcd quorum loss (HA)

```bash
make check-etcd-health
make check-etcd-members
```

If not 3/3 healthy: see [`runbooks/05-incident-response.en.md § etcd quorum loss`](./runbooks/05-incident-response.en.md).

### Remote command execution (debugging)

```bash
make cmd-all CMD="systemctl status kubelet"
make cmd-masters CMD="kubectl get nodes"
make cmd-host HOST="worker1" CMD="nerdctl ps"
```

## HA Cluster IP Change

Procedure for changing master IPs in a 3-master HA cluster. Detailed scenarios: [`runbooks/04-node-ip-change.en.md`](./runbooks/04-node-ip-change.en.md).

### Single master vs HA differences

| Aspect | Single master | HA (3-master) |
|------|---------------|---------------|
| etcd handling | `--force-new-cluster` | `etcdctl member update` |
| Quorum | N/A | Must keep 2/3 |
| Execution | Single host | Sequential (one at a time) |

### Command summary

```bash
# Pre-check
make check-etcd-health
make check-etcd-members

# === Master 1 change ===
vi inventory.ini    # master1 ansible_host=192.168.1.81 (new IP)
make update-ha-ip OLD_IP=192.168.1.71 NEW_IP=192.168.1.81 HOST=master1
make check-etcd-health      # confirm 2/3 healthy before proceeding to next master

# === Master 2 ===
vi inventory.ini
make update-ha-ip OLD_IP=192.168.1.72 NEW_IP=192.168.1.82 HOST=master2
make check-etcd-health

# === Master 3 ===
vi inventory.ini
make update-ha-ip OLD_IP=192.168.1.73 NEW_IP=192.168.1.83 HOST=master3
make check-etcd-health
make check-etcd-members
kubectl get nodes
```

### With domain communication (recommended)

When `enable_domain_communication: true`, etcd uses hostname-based addressing — IP change requires only `/etc/hosts` updates → safer + faster.

### Cautions

- Wait at least 30 seconds between master changes (etcd stabilization)
- **Always keep 2/3 masters healthy** before next change
- On failure, can recover by reverting to `OLD_IP`
- If IP is in cert SAN, use `update-ha-ip-with-certs`

## Additional Resources

- [Kubernetes documentation](https://kubernetes.io/docs/)
- [kubectl cheatsheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [kubeadm reference](https://kubernetes.io/docs/reference/setup-tools/kubeadm/)
- [Cilium documentation](https://docs.cilium.io/)
- [Flannel documentation](https://github.com/flannel-io/flannel)
- [containerd documentation](https://containerd.io/)
- [Ansible documentation](https://docs.ansible.com/)

## ✨ Highlights

- ✅ **Fully automated**: deploy entire cluster with one command
- ✅ **Version compatible**: K8s 1.27.x – 1.34.x, containerd 1.7.x – 2.2.x
- ✅ **CNI choice**: Flannel or Cilium (with offline install support)
- ✅ **High availability**: kube-vip or domain-based HA
- ✅ **OIDC integration**: kube-apiserver + Keycloak or other external IdPs
- ✅ **Registry mirror**: auto-redirect external registries to internal mirror
- ✅ **GPU support**: auto driver install + node labeling
- ✅ **Custom CA**: install self-signed certs into system trust store
- ✅ **Cert management**: 10-year auto-extension
- ✅ **Cluster validation**: 5-step automated health check
- ✅ **Offline install**: APT/YUM/Cilium internal mirror support
- ✅ **Cross-platform**: Ubuntu / RHEL / Rocky / CentOS
- ✅ **Auto worker add**: detect unregistered nodes
- ✅ **Runbooks**: 7 step-by-step scenario SOPs (KO/EN)

## Contributing / License

Issues and pull requests welcome. MIT License.

---

**Made with ❤️ for Kubernetes Administrators**
