# 01 — Day-0 Cluster Install

> **Language / 언어:** [한국어](./01-day0-install.md) · [English](./01-day0-install.en.md)
> **Risk:** Medium · **Duration:** 30–90 min

## Purpose

Deploy a new Kubernetes cluster from scratch. Three scenarios depending on environment, all following the same 4-step structure (pre-check → edit config → run → verify).

## Risk Level

**Medium** — First install is idempotent; on failure, `make reset` and retry. However, re-running `make install` on an existing cluster will reinstall some components and may cause brief downtime.

## Preconditions

- [ ] [00 Prerequisites](./00-prerequisites.en.md) completed (SSH, inventory, group_vars edited)
- [ ] All hosts respond to `make ping`
  ```bash
  make ping
  # Expected: master1 | SUCCESS => { "ping": "pong" }, ...
  ```
- [ ] Per-host minimum spec met (master 4GB RAM/2 cores, worker 2GB/2 cores)
- [ ] Swap is permanently off, or sysctl applies it during install
- [ ] Time sync available on all nodes (NTP or master1 as NTP server)

## Scenario A — Single Master (Online, ~15 min)

### A-1. Pre-flight
```bash
make ping                # all hosts SUCCESS
make test-connection     # group-by-group ping
make show-inventory      # inventory tree
```

### A-2. Edit `group_vars/all.yml`
First time: `cp group_vars/all.yml.example group_vars/all.yml` then edit.

```yaml
# Key changes (single master + internet)
master_ha: false
network_plugin: "flannel"             # or "cilium"
allow_master_scheduling: true         # single node requires true
enable_domain_communication: false
docker_login_required: false
enable_registry_mirror: false
enable_oidc_apiserver: false
extend_k8s_certificates: true
```

### A-3. Run
```bash
make install
# Or stepped (for debugging)
make install-step1   # sysctl + packages + containerd
make install-step2   # K8s (kubeadm init/join)
make install-step3   # CNI plugin
```

Success output (last lines):
```
PLAY RECAP *********************************************************************
master1 : ok=42  changed=18  unreachable=0  failed=0  skipped=5
```

### A-4. Validate
```bash
make validate
```
Success:
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

On failure → [05 Incident response](./05-incident-response.en.md) for scenario-specific diagnosis.

## Scenario B — Offline Install (Air-gapped, ~30 min)

### B-1. Pre-staging (on a host with internet)

1. **Internal mirror server**: Apache/Nginx hosting OS packages, K8s packages, container images
2. **Pre-download Cilium CLI** (if using Cilium)
   ```bash
   curl -LO https://github.com/cilium/cilium-cli/releases/download/v0.16.8/cilium-linux-amd64.tar.gz
   mv cilium-linux-amd64.tar.gz roles/install_cilium/files/
   ```
3. **Push K8s container images** to internal Harbor (`harbor.example.com/external-hub/kubernetes/...`)

### B-2. Edit `group_vars/all.yml`

```yaml
# Internal repos
enable_official_k8s_repo: false
enable_official_containerd_repo: false

# Ubuntu internal APT
enable_ubuntu_repo: true
ubuntu_repo_url: "http://mirror.example.com/ubuntu-repo"

# RHEL internal YUM (multiple allowed)
enable_rhel_repos: true
rhel_repos:
  - name: "rhel-iso-repo"
    id: "rhel-iso-repo"
    url: "http://mirror.example.com/rhel-repo"
    type: "baseos_appstream"
    enabled: 1
    gpgcheck: 0
    priority: 1

# K8s component images
enable_custom_image_repository: true
k8s_image_repository: "harbor.example.com/external-hub/kubernetes"
coredns_image_repository: "harbor.example.com/external-hub/kubernetes/coredns"
pause_image: "harbor.example.com/external-hub/kubernetes/pause:3.10"

# Cilium offline
network_plugin: "cilium"
cilium_offline_install: true
cilium_image_repository: "harbor.example.com/cilium"

# External registry mirror
enable_registry_mirror: true
registry_mirror_host: "harbor.example.com"
registry_mirror_user: "<your-username>"
registry_mirror_password: "<your-password>"

# Override validation external URL (google.com is blocked)
validation_external_url: "http://harbor.example.com/health"
```

### B-3. Run
```bash
make install
```

### B-4. Validate
```bash
make validate
# External check redirected to internal host (validation_external_url)
```

Or skip external check:
```bash
make check-cluster   # node/Pod status only
```

## Scenario C — HA 3-Master (~45 min)

### C-1. Pre-flight
```bash
make ping
make show-inventory   # confirm 3 nodes in [masters]
```

### C-2. Inventory
```ini
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

### C-3. Edit `group_vars/all.yml`

#### Option 1: kube-vip
```yaml
master_ha: true
kube_vip_address: 192.168.1.30        # unused VIP
kube_vip_port: 6443
kube_vip_interface: ens18              # verify with `ip link show`
allow_master_scheduling: false        # production: false
extend_k8s_certificates: true
```

#### Option 2: Domain-based (external LB)
```yaml
master_ha: true
enable_domain_communication: true
domain_suffix: "k8s.local"
api_domain: "k8s-api.internal"
# kube_vip_address is NOT defined

# DNS or /etc/hosts must resolve api_domain to first master IP
custom_hosts:
  "k8s-api.internal": "192.168.1.31"
```

### C-4. Run
```bash
make install   # site.yml installs masters serial:1 (avoids etcd race)
```

Per-master logs appear sequentially (master1 → master2 → master3 → workers parallel).

### C-5. Validate
```bash
make check-etcd-health      # 3/3 nodes healthy
make check-etcd-members     # member list
make check-cluster
make validate
```

Success example (`make check-etcd-health`):
```
{"endpoint": "192.168.1.31:2379", "health": "true"}
{"endpoint": "192.168.1.32:2379", "health": "true"}
{"endpoint": "192.168.1.33:2379", "health": "true"}
```

## Verification

```bash
# 1. Cluster health
make validate

# 2. (HA only) etcd
make check-etcd-health
make check-etcd-members

# 3. Versions
make check-versions

# 4. Pod details
kubectl get pods -A -o wide
```

## Rollback

When install fails or you want to start over:

```bash
# Full cluster reset
make reset

# Or workers only
make reset-workers

# Reset + reboot
make reset-and-reboot
```

⚠️ **Data loss**: etcd, PVs, container images all destroyed. In production, review the [06 Cluster reset](./06-cluster-reset.en.md) backup checklist first.

## FAQ

### Q1. `make install` halts mid-way. Safe to re-run?
A. Yes — the playbook is idempotent. Re-running is safe. Faster: identify which phase failed in the log → run only that phase via tag (`make tag-kubernetes`, etc.).

### Q2. Swap turns off but comes back after reboot.
A. `configure_sysctl` role comments out swap in `/etc/fstab`. If it still re-enables:
```bash
ssh <node>
sudo cat /etc/fstab | grep -i swap
sudo systemctl mask swap.target  # forcibly disable
```

### Q3. In HA, master2/master3 join fails.
A. Most common causes:
- `kube_vip_interface` doesn't match the actual NIC → check `ip link show`
- `kube_vip_address` already in use → pick another unused IP
- For domain communication, `api_domain` DNS not configured → add to `custom_hosts`
- Details: [05 Incident response § etcd quorum loss](./05-incident-response.en.md)

### Q4. After Cilium install, `cilium status` hangs for a long time.
A. `cilium status --wait` waits up to 30 retries × 10s = 5 min. If still stuck:
```bash
ssh master1
kubectl -n kube-system get pods -l k8s-app=cilium
kubectl -n kube-system describe pod <cilium-pod>
```
Image pull failure is most common → check `cilium_image_repository` or internet connectivity.

### Q5. In air-gapped env, `make validate` fails on external check.
A. The external check uses `validation_external_url` (default `http://google.com`). For isolated environments:
```yaml
# Add to group_vars/all.yml
validation_external_url: "http://harbor.example.com/health"
```
Or use `make check-cluster` instead of `make validate`.

### Q6. After install, `kubectl` doesn't work.
A. On master1:
```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
kubectl get nodes
```

## Related docs

- [00 Prerequisites](./00-prerequisites.en.md)
- [05 Incident response](./05-incident-response.en.md)
- [06 Cluster reset](./06-cluster-reset.en.md)
- [README.en.md](../README.en.md)
- [`group_vars/all.yml.example`](../group_vars/all.yml.example) — All variables with detailed comments
