# 06 — Cluster Reset & Redeploy

> **Language / 언어:** [한국어](./06-cluster-reset.md) · [English](./06-cluster-reset.en.md)
> **Risk:** High (irreversible) · **Duration:** 15–60 min

## Purpose

Reset the cluster to its initial state (full or workers only). Includes pre-cleanup for stateful components like rook-ceph.

## ⚠️ Data Loss Warning

**Reset is irreversible.** The following data is destroyed:
- etcd (all K8s resource metadata)
- PV / PVC (especially hostPath, local-path-provisioner)
- Container image cache (`/var/lib/containerd`)
- Pod logs (`/var/log/pods`)
- kubelet state (`/var/lib/kubelet`)
- CNI config (`/etc/cni/net.d`)

**Preserved**:
- NFS volumes (if on a separate NFS server)
- External DB / external storage (external Ceph clusters, S3, etc.)
- Harbor / external registry images

## Pre-Reset Backup Checklist

Before reset, verify:

- [ ] **etcd snapshot** (enables fast restore on rebuild):
  ```bash
  ssh master1 "sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    snapshot save /var/lib/etcd-pre-reset.db"
  ```

- [ ] **PV data** (copy to other storage if needed):
  ```bash
  kubectl get pv
  # Check ReclaimPolicy=Retain
  ```

- [ ] **Critical ConfigMap/Secret backup**:
  ```bash
  kubectl get cm,secret -A -o yaml > backup-cm-secret.yaml
  ```

- [ ] **User manifests backup**:
  ```bash
  kubectl get all,ingress,pvc -A -o yaml > backup-resources.yaml
  ```

- [ ] **`group_vars/all.yml` backup** (use same config on reinstall):
  ```bash
  cp group_vars/all.yml /tmp/all.yml.backup
  ```

## Scenario 1 — Full reset

### Without rook-ceph

```bash
# 1. Pre-backup (checklist above)

# 2. Run reset
make reset
# kubeadm reset + cleanup /etc/kubernetes/* + /var/lib/kubelet/* + /var/lib/etcd/* on all nodes

# Or reset + reboot
make reset-and-reboot
```

`reset_cluster.yml` does:
- `kubeadm reset -f`
- Clean `/etc/kubernetes/`, `/var/lib/kubelet/`, `/var/lib/etcd/`
- Clean iptables rules
- Clean CNI config (`/etc/cni/net.d/`)

### With Rook-Ceph

CRD deletion needs a live K8s API → **clean up before reset**.

```bash
# 1. Enable in group_vars/all.yml
# enable_rook_ceph_cleanup: true

# 2. Cleanup rook-ceph + reset cluster
make reset-rook-ceph
# Or stepped
ansible-playbook -i inventory.ini cleanup-rook-ceph.yml
make reset
```

`cleanup_rook_ceph` role safely deletes CephCluster, CephBlockPool, etc. CRDs → then `make reset`.

## Scenario 2 — Workers only

For testing new K8s versions while reusing the control plane.

```bash
# 1. Drain workers (move workloads to masters; works for small clusters)
ansible workers -i inventory.ini -m shell -a "kubectl drain $(hostname) --ignore-daemonsets --delete-emptydir-data"

# 2. Reset workers
make reset-workers

# 3. Reinstall (inventory unchanged)
make install-step1   # system prep
make install-step2   # K8s join
```

## Scenario 3 — Single-node reset (for re-join)

Reset only a problem node and re-join.

```bash
# 1. Remove from cluster
kubectl drain worker3 --ignore-daemonsets --delete-emptydir-data
kubectl delete node worker3

# 2. Reset only that node
ansible-playbook -i inventory.ini reset_cluster.yml --limit worker3

# 3. Re-add
make check-and-add-workers
```

## Verification

Confirm all nodes are in clean state after reset:

```bash
# 1. K8s components stopped
make cmd-all CMD="systemctl status kubelet | head -3"
# expected: Active: inactive (dead)

make cmd-all CMD="systemctl status containerd | head -3"
# expected: Active: active (containerd itself runs; only K8s removed)

# 2. K8s directories cleaned
make cmd-all CMD="ls /etc/kubernetes/ 2>&1 | head -5"
# expected: directory absent or nearly empty

# 3. Containers cleaned
make cmd-all CMD="crictl ps -a"
# expected: nearly empty

# 4. iptables cleaned
make cmd-masters CMD="iptables -t nat -L KUBE-SERVICES 2>&1 | head -3"
# expected: 'No chain' or empty chain
```

## Rollback

**Reset is irreversible** — no true rollback. Options:

### Option 1: Fast rebuild via pre-staged etcd snapshot
```bash
# 1. Reinstall cluster
make install

# 2. Restore etcd data (on master1)
ssh master1
sudo systemctl stop kubelet
sudo ETCDCTL_API=3 etcdctl snapshot restore /var/lib/etcd-pre-reset.db --data-dir=/var/lib/etcd-restore
sudo mv /var/lib/etcd /var/lib/etcd.new
sudo mv /var/lib/etcd-restore /var/lib/etcd
sudo systemctl start kubelet
```

### Option 2: Re-deploy workloads from manifest backups
```bash
# After fresh cluster install
kubectl apply -f backup-resources.yaml
kubectl apply -f backup-cm-secret.yaml
```

### Option 3: Restore code from git tag (if config change was the issue)
```bash
git tag -l "backup/*"
# backup/pre-doc-refresh-20260507
git reset --hard backup/pre-doc-refresh-20260507
```

## FAQ

### Q1. `make install` fails after `make reset`.
A. Most common causes:
- Stale iptables rules → `sudo iptables -F && sudo iptables -t nat -F && sudo iptables -X`
- Stale containerd containers → `sudo crictl rm -af && sudo systemctl restart containerd`
- Still failing → `make reset-and-reboot` to reboot

### Q2. PV is Retain so data is alive — how to attach to new cluster?
A. Re-apply PV manifest with claimRef removed:
```bash
kubectl get pv <pv-name> -o yaml > pv.yaml
# Edit pv.yaml: delete spec.claimRef section → re-apply
kubectl apply -f pv.yaml
```

### Q3. I ran `make reset` without cleaning up Rook-Ceph.
A. CRD finalizers prevent cleanup until K8s API is alive again. Two options:
1. Reinstall cluster, redeploy rook-ceph on same disks (Ceph reads disk headers, recognizes existing cluster)
2. Wipe disk directly: `sudo dd if=/dev/zero of=/dev/sdb bs=1M count=100`

### Q4. After worker-only reset and rejoin, GPU not detected.
A. NVIDIA driver is preserved, but containerd config is reset → NVIDIA runtime needs reconfig:
```bash
make tag-nvidia --limit worker3
# Or
make configure-gpu-full
```

### Q5. After reset, `/etc/kubernetes/` still has files.
A. Role does additional cleanup post-`kubeadm reset`, but permission issues may leave residual files:
```bash
ssh worker3 "sudo rm -rf /etc/kubernetes/* /var/lib/kubelet/* /var/lib/etcd/*"
```

## Related docs

- [01 Day-0 install](./01-day0-install.en.md) — reinstall after reset
- [05 Incident response](./05-incident-response.en.md)
- `cleanup-rook-ceph.yml`, `roles/cleanup_rook_ceph/`
- `reset_cluster.yml`, `roles/reset_k8s_cluster/`
