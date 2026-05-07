# 02 — Add or Remove Worker Node

> **Language / 언어:** [한국어](./02-add-worker.md) · [English](./02-add-worker.en.md)
> **Risk:** Medium · **Duration:** 15–30 min

## Purpose

Add a new Worker node to an existing cluster, or safely remove one.

## Preconditions

- [ ] Existing cluster healthy (`make check-cluster`)
- [ ] **For add**: new node OS installed, SSH key distributed, `inventory.ini` updated
- [ ] **For remove**: enough capacity on remaining nodes for that worker's workloads

## Add Worker

### Method 1 — Auto-detect (recommended)
```bash
# 1. Add new worker to inventory.ini
vi inventory.ini
# [workers]
# worker3 ansible_host=192.168.1.43

# 2. Auto-detect + join
make check-and-add-workers
```

`check-and-add-workers.yml` compares inventory to `kubectl get nodes` and auto-joins only the missing nodes.

### Method 2 — Manual add
```bash
# After updating inventory.ini
make add-workers
# Or limit to specific host
ansible-playbook -i inventory.ini add-worker.yml --limit worker3
```

### Method 3 — Direct kubeadm
```bash
make get-join-command
# Output: kubeadm join 192.168.1.31:6443 --token abc.xyz --discovery-token-ca-cert-hash sha256:...

ssh worker3
sudo <join-command>
```

### Verify
```bash
make check-workers
# Or
kubectl get nodes -o wide
# worker3   Ready   <none>   2m   v1.34.1   192.168.1.43

make validate
```

worker3 should appear as `Ready` (1-2 min after CNI Pod deploys).

## Remove Worker

### Procedure (safe drain → delete)

#### 1. Migrate workloads
```bash
# Mark node unschedulable
kubectl cordon worker3

# Move pods to other nodes (drain)
kubectl drain worker3 \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=120 \
  --timeout=300s
```

`--ignore-daemonsets`: kube-proxy, CNI are auto-recreated, so ignore them.

#### 2. Remove from cluster
```bash
kubectl delete node worker3
```

#### 3. Reset the node itself (for reuse)
```bash
# After removing from inventory.ini
make reset-workers --limit worker3
# Or directly
ssh worker3 "sudo kubeadm reset -f"
ssh worker3 "sudo rm -rf /etc/cni/net.d /var/lib/cni/ /var/lib/kubelet/*"
```

### Verify
```bash
kubectl get nodes
# worker3 removed from list

make check-cluster
```

## FAQ

### Q1. Join token expired.
A. Tokens valid 24 hours by default. Issue new:
```bash
make get-join-command
# Or
ssh master1 "sudo kubeadm token create --print-join-command"
```

### Q2. `make check-and-add-workers` tries to re-join all workers.
A. Happens when inventory hostname differs from cluster node name.
```bash
# Check cluster node names
kubectl get nodes
# Confirm same hostname as inventory.ini
```
Verify `ansible_hostname` or `set_hostname_from_inventory: true` consistency.

### Q3. Drain hangs (PDB or emptyDir).
A.
- PDB conflict: `kubectl get pdb` → temporarily relax PDB
- emptyDir data: add `--delete-emptydir-data` (already included above)
- Permanent hang: `kubectl drain --force` (but standalone Pods outside RC/Job will be deleted)

### Q4. New node stays NotReady.
A. Verify CNI Pod arrived:
```bash
kubectl -n kube-flannel get pods -o wide   # Flannel
# Or
kubectl -n kube-system get pods -l k8s-app=cilium -o wide
```
If a Pod for `worker3` exists and is Running, wait 1-2 min more. CrashLoop → see [05 Incident response § CNI failure](./05-incident-response.en.md).

### Q5. Re-adding a node with the same hostname is rejected.
A. After `kubectl delete node`, the node's `/var/lib/kubelet`, `/etc/kubernetes`, `/etc/cni/net.d` must be cleaned for clean re-add. Use `make reset-workers --limit <host>`.

## Related docs

- [`ADD-WORKER-GUIDE.md`](../ADD-WORKER-GUIDE.md) — detailed (preserved as legacy detail)
- [05 Incident response](./05-incident-response.en.md)
- [06 Cluster reset](./06-cluster-reset.en.md)
