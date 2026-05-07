# 05 — Incident Response

> **Language / 언어:** [한국어](./05-incident-response.md) · [English](./05-incident-response.en.md)
> **Risk:** varies (per scenario) · **Duration:** immediate

## Purpose

Diagnose → root-cause → remediate common failures in a running cluster. Search by symptom → jump to scenario section.

## Quick Lookup

| Symptom | Section | Risk |
|---|---|---|
| Node `NotReady` | [Node NotReady](#node-notready) | Medium |
| HA cluster API hangs / `kubectl` stuck | [etcd quorum loss](#etcd-quorum-loss) | High |
| Pod stuck in `ContainerCreating` | [CNI failure (Flannel)](#cni-failure-flannel) / [CNI failure (Cilium)](#cni-failure-cilium) | Medium |
| `ErrImagePull` / `ImagePullBackOff` | [Image pull failure](#image-pull-failure) | Low–Medium |
| `kubectl` auth rejected (after OIDC) | [OIDC auth failure](#oidc-auth-failure) | Medium |
| Registry mirror unreachable | [Registry mirror outage](#registry-mirror-outage) | Medium |

---

## Node NotReady

### Symptom
```bash
kubectl get nodes
# NAME      STATUS     ROLES           AGE   VERSION
# worker1   NotReady   <none>          12m   v1.34.1
```

### Diagnose (1 min)
```bash
# 1. kubelet status
ssh worker1 "sudo systemctl status kubelet"

# 2. kubelet logs (last 100 lines)
ssh worker1 "sudo journalctl -u kubelet -n 100 --no-pager"

# 3. CNI status (most common cause)
kubectl describe node worker1 | grep -A 5 Conditions

# 4. CNI Pod (Flannel/Cilium)
kubectl get pods -n kube-flannel -o wide       # Flannel
kubectl get pods -n kube-system -l k8s-app=cilium -o wide   # Cilium
```

### Cause → Fix

**Cause 1: containerd down**
```bash
ssh worker1 "sudo systemctl status containerd"
# Active: failed (Result: exit-code) ...

# Fix
ssh worker1 "sudo systemctl start containerd && sudo systemctl status containerd"
# Or reapply
make tag-container --limit worker1
```

**Cause 2: swap is on**
```bash
ssh worker1 "swapon --show"
# (any output = swap on)

# Fix
ssh worker1 "sudo swapoff -a"
ssh worker1 "sudo sed -i '/swap/s/^/#/' /etc/fstab"
# Or
make tag-sysctl --limit worker1
```

**Cause 3: CNI not installed or damaged**
```bash
# If CNI Pod is 0/1 or CrashLoopBackOff
kubectl get pods -n kube-flannel
# Or
kubectl get pods -n kube-system -l k8s-app=cilium

# Fix: reinstall CNI
make tag-networking
```

**Cause 4: image pull failure** → see [Image pull failure](#image-pull-failure)

### Verify
```bash
kubectl get nodes
# All nodes Ready
make validate
```

---

## etcd quorum loss

### Symptom
- `kubectl` commands hang / time out
- After restarting some masters in HA cluster
- API server logs: `etcdserver: request timed out`

### Diagnose (High risk — go slow)
```bash
# 1. etcd healthcheck
make check-etcd-health
# Healthy = all endpoints health=true. Any false = quorum at risk.

# 2. Member list
make check-etcd-members

# 3. etcd container status per master
ansible masters -i inventory.ini -m shell -a "crictl ps | grep etcd"
```

### Cause → Fix

**Cause 1: 1 master down (2/3 healthy)**
- Quorum maintained → cluster works (briefly slow)
- Recover the down master:
  ```bash
  ssh master2 "sudo systemctl status kubelet containerd"
  # Restart if needed
  ssh master2 "sudo systemctl restart kubelet"
  ```

**Cause 2: 2+ masters down (quorum lost)**
- Very dangerous — possible data loss
- **If etcd backup exists**, restore as single-node:
  ```bash
  # On master1
  ssh master1 "sudo ETCDCTL_API=3 etcdctl snapshot restore /var/lib/etcd-backup/snapshot.db ..."
  # See etcd official docs for full procedure
  ```
- No backup: cluster rebuild + restore from PV data may be fastest → [06 Cluster reset](./06-cluster-reset.en.md)

**Cause 3: Member URL out of sync after IP change**
- Most common — happens after IP change ops
- Fix: verify [04 Node IP change](./04-node-ip-change.en.md) HA procedure was followed exactly
- Re-run `roles/update_node_ip/tasks/etcd_member_update.yml`

### Verify
```bash
make check-etcd-health   # 3/3 healthy
kubectl get cs           # ComponentStatuses (deprecated but useful)
```

---

## CNI failure (Flannel)

### Symptom
- Pod stuck in `ContainerCreating`
- `kubectl describe pod` events: `failed to set up sandbox container ... network: ...`

### Diagnose
```bash
kubectl get pods -n kube-flannel -o wide
kubectl logs -n kube-flannel -l app=flannel --tail=50
```

### Cause → Fix

**Cause 1: Flannel DaemonSet Pod CrashLoop**
```bash
kubectl describe pod -n kube-flannel <flannel-pod>
# Events: ... ImagePullBackOff
```
→ Image pull failure. See [Image pull failure](#image-pull-failure).

**Cause 2: pod_subnet mismatch**
- `pod_subnet` in `group_vars/all.yml` differs from Flannel ConfigMap's `Network`.
- Fix: `kubectl get cm kube-flannel-cfg -n kube-flannel -o yaml`, align them, or reinstall:
  ```bash
  make tag-networking
  ```

**Cause 3: `net.bridge.bridge-nf-call-iptables` not set**
```bash
ssh worker1 "sysctl net.bridge.bridge-nf-call-iptables"
# net.bridge.bridge-nf-call-iptables = 0 (wrong)
make tag-sysctl
```

---

## CNI failure (Cilium)

### Diagnose
```bash
# Cilium CLI (on master1)
ssh master1
cilium status                           # overall status
cilium connectivity test --quick        # connectivity test

# Or pod status
kubectl -n kube-system get pods -l k8s-app=cilium -o wide
```

### Cause → Fix

**Cause 1: cilium-agent CrashLoopBackOff**
```bash
kubectl -n kube-system describe pod <cilium-agent-pod>
kubectl -n kube-system logs <cilium-agent-pod>
```
- Most common: image pull failure → check `cilium_image_repository`
- Or kernel compatibility (old kernel) → check `uname -r` (≥5.4 recommended)

**Cause 2: Hubble not starting**
```bash
cilium hubble enable
cilium status --wait
```

**Cause 3: kube-proxy replacement (strict mode) conflict**
- `cilium_kube_proxy_replacement: strict` set, but `kube-proxy` still alive
- Fix: delete kube-proxy DaemonSet
  ```bash
  kubectl -n kube-system delete daemonset kube-proxy
  ```

### Verify
```bash
cilium status
make validate
```

---

## Image pull failure

### Symptom
- `kubectl get pods` → `ErrImagePull` / `ImagePullBackOff`
- `kubectl describe pod`: `Failed to pull image: ... 401 Unauthorized` or `i/o timeout`

### Diagnose
```bash
# 1. Detailed events
kubectl describe pod <pod>

# 2. Test pull directly on the node
ssh worker1
sudo nerdctl pull harbor.example.com/library/nginx:latest
# Or crictl
sudo crictl pull harbor.example.com/library/nginx:latest

# 3. containerd auth config
sudo cat /etc/containerd/config.toml | grep -A 10 registry
sudo ls /etc/containerd/certs.d/
sudo cat /etc/containerd/certs.d/<host>/hosts.toml
```

### Cause → Fix

**Cause 1: Auth error (401/403)**
```yaml
# Verify group_vars/all.yml
docker_registries:
  - registry: "harbor.example.com"
    username: "<correct-username>"
    password: "<correct-password>"
```
→ Re-run `make tag-docker-credentials`

**Cause 2: Untrusted CA (self-signed Harbor)**
```yaml
enable_ca_certificates: true
ca_certificates:
  - name: "harbor-ca"
    url: "https://harbor.example.com/ca.crt"
```
→ `make tag-ca-certificates` or `make tag-docker-credentials`

**Cause 3: Mirror config error**
```bash
# Check hosts.toml
ssh worker1 "sudo cat /etc/containerd/certs.d/docker.io/hosts.toml"
# server = "https://docker.io"
# [host."https://harbor.example.com/v2/docker-io"]
#   capabilities = ["pull", "resolve"]
```
→ Add missing mappings to `registry_mirror_mappings`, then `make tag-registry-mirror`

**Cause 4: Network blocked**
- Air-gapped env trying to reach external registry
- Fix: `enable_registry_mirror: true` + use internal Harbor

### Verify
```bash
kubectl get pods -A | grep -v Running | grep -v Completed
# Empty output = all good
```

---

## Registry mirror outage

### Symptom
- All nodes suddenly fail to pull external images
- `harbor.example.com` itself down

### Diagnose
```bash
# Harbor self-healthcheck (separate infra)
curl -s https://harbor.example.com/api/v2.0/health

# Verify hosts.toml behavior on a node
ssh worker1
sudo crictl pull docker.io/library/busybox:1.36
# Confirm redirect to mirror
sudo journalctl -u containerd | grep -i pull | tail -20
```

### Cause → Fix

**Cause 1: Internal Harbor down → temporary fallback**
```bash
# Temporarily disable mirror on all nodes
ansible all -i inventory.ini -m shell -a "sudo mv /etc/containerd/certs.d /etc/containerd/certs.d.disabled"
ansible all -i inventory.ini -m systemd -a "name=containerd state=restarted"

# After Harbor recovers
ansible all -i inventory.ini -m shell -a "sudo mv /etc/containerd/certs.d.disabled /etc/containerd/certs.d"
ansible all -i inventory.ini -m systemd -a "name=containerd state=restarted"
```

**Cause 2: hosts.toml credentials expired**
- After `registry_mirror_password` rotation → re-run `make tag-registry-mirror`

---

## OIDC auth failure

### Symptom
- `kubectl` commands return `Unauthorized` / `error: You must be logged in to the server`
- Right after enabling OIDC

### Diagnose
```bash
# 1. API server logs
ssh master1 "kubectl -n kube-system logs kube-apiserver-master1 | grep -i oidc"

# 2. OIDC flags in API server manifest
ssh master1 "sudo grep oidc /etc/kubernetes/manifests/kube-apiserver.yaml"

# 3. JWKS endpoint connectivity
ssh master1 "curl -k https://keycloak.example.com/realms/example/.well-known/openid-configuration"
```

### Cause → Fix

**Cause 1: API server fails to start after OIDC config**
- Roll back via backup file:
  ```bash
  ssh master1
  sudo ls /etc/kubernetes/kube-apiserver.yaml.backup-*
  sudo cp /etc/kubernetes/kube-apiserver.yaml.backup-<latest-epoch> /etc/kubernetes/manifests/kube-apiserver.yaml
  # kubelet auto-restarts the Pod
  ```

**Cause 2: IdP cert not trusted**
```yaml
# group_vars/all.yml
oidc_ca_file: "/etc/kubernetes/pki/idp-ca.crt"
```
→ Pre-place CA file on masters, then `make tag-oidc-apiserver`

**Cause 3: Wrong groups_claim**
- `oidc_groups_claim` doesn't match the actual claim in JWT issued by IdP
- Decode IdP token (jwt.io) → check actual claim name

### Rollback (emergency)
```bash
# Disable OIDC on all masters
ansible masters -i inventory.ini -m shell \
  -a "sudo cp /etc/kubernetes/kube-apiserver.yaml.backup-* /etc/kubernetes/manifests/kube-apiserver.yaml"
# Falls back to certificate authentication
```

---

## FAQ

### Q1. `kubectl get nodes` shows all NotReady — where to start?
A. 90% of cases: containerd or CNI. Order:
1. `ssh master1 "sudo systemctl status containerd"`
2. `kubectl get pods -A | grep -v Running`
3. Inspect CNI Pod logs

### Q2. Multiple nodes NotReady at once. Did the whole cluster die?
A. If masters (API server) are alive, worker NotReady is recoverable. First:
```bash
make check-cluster   # verify masters respond
make check-etcd-health  # HA: confirm etcd healthy
```
If both healthy → diagnose per worker → [Node NotReady](#node-notready).

### Q3. What should I absolutely NOT do during incident response?
A. **Don't casually restart masters when etcd quorum is lost.** Going from 2/3 to 1/3 makes recovery extremely hard. First check `make check-etcd-health` to understand state, then act.

### Q4. I tried all the diagnoses but can't find the cause.
A. Check OS-level resource/kernel messages:
```bash
make cmd-all CMD="dmesg | tail -50"
make cmd-all CMD="df -h"
make cmd-all CMD="free -h"
```
Often-overlooked causes: disk full, OOM, auto-reboot after kernel panic.

## Related docs

- [04 Node IP change](./04-node-ip-change.en.md)
- [06 Cluster reset](./06-cluster-reset.en.md)
- [README.en.md § Troubleshooting](../README.en.md)
- `roles/update_node_ip/tasks/etcd_member_update.yml`
- `roles/install_cilium/tasks/main.yml`
