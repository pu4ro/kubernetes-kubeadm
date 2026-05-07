# 04 — Node IP Change

> **Language / 언어:** [한국어](./04-node-ip-change.md) · [English](./04-node-ip-change.en.md)
> **Risk:** High · **Duration:** 30–90 min

## Purpose

Auto-update Kubernetes manifests, etcd member URLs, and kubeconfig when a master/worker IP changes.

## Affected files

The `update_node_ip` role updates:
- `/etc/kubernetes/manifests/etcd.yaml`
- `/etc/kubernetes/manifests/kube-apiserver.yaml`
- `/etc/kubernetes/manifests/kube-controller-manager.yaml`
- `/etc/kubernetes/manifests/kube-scheduler.yaml`
- `/etc/kubernetes/admin.conf`, `kubelet.conf`, `controller-manager.conf`, `scheduler.conf`
- `/etc/hosts`
- `~/.kube/config`

Each file is auto-backed up to `.bak`.

## Preconditions

- [ ] **etcd backup recommended** (mandatory for HA)
- [ ] New IP is unused and on the same subnet
- [ ] DNS or `custom_hosts` pre-updated
- [ ] `make check-cluster` healthy
- [ ] (HA only) `make check-etcd-health` — 3/3 healthy before starting

## Scenario routing

| Scenario | Command |
|---|---|
| Single master (no IP in cert SAN) | `make update-ip` |
| Single master (IP in cert SAN) | `make update-ip-with-certs` |
| HA multi-master | `make update-ha-ip` (one at a time) |
| HA + domain communication | `/etc/hosts` update only (simplified) |

---

## Scenario 1 — Single master

### 1-1. Pre-flight
```bash
make check-cluster
make check-versions

# Current IP
ssh master1 "ip addr show ens18"
```

### 1-2. Edit inventory
```ini
# inventory.ini
[masters]
master1 ansible_host=192.168.1.100   # new IP
```

### 1-3. Run IP change

#### IP NOT in cert SAN
```bash
make update-ip OLD_IP=192.168.1.41 NEW_IP=192.168.1.100 HOST=master1
```

#### IP IS in cert SAN (kubeadm init adds master IP to SAN)
```bash
make update-ip-with-certs OLD_IP=192.168.1.41 NEW_IP=192.168.1.100 HOST=master1
```

### 1-4. Verify
```bash
make check-cluster
make validate
ssh master1 "kubectl get nodes -o wide"
```

---

## Scenario 2 — HA multi-master (most dangerous, go slow)

### Core principles
1. **One master at a time** (protect etcd quorum)
2. **Wait 30+ seconds after each change** (etcd stabilization)
3. **Verify 2/3 healthy via `make check-etcd-health`** before next master
4. On failure, can recover by reverting to `OLD_IP`

### 2-1. Pre-state backup
```bash
make check-etcd-health    # confirm 3/3 healthy
make check-etcd-members   # preserve member list
make check-cluster

# (Optional) etcd snapshot
ssh master1 "sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /var/lib/etcd-backup-pre-ip-change.db"
```

### 2-2. Change Master 1

#### Edit inventory
```bash
vi inventory.ini
# master1 ansible_host=192.168.1.81   # new IP
```

#### Run
```bash
make update-ha-ip OLD_IP=192.168.1.71 NEW_IP=192.168.1.81 HOST=master1
```

`update_node_ip` role does:
1. Stop kubelet
2. Replace IPs in manifest/conf files
3. Update etcd member URL (`etcdctl member update`)
4. Start kubelet
5. Update `/etc/hosts`, `~/.kube/config`

#### Verify
```bash
sleep 30                  # wait for etcd stabilization
make check-etcd-health    # confirm 3/3 healthy (master2, master3 + master1 with new IP)
make check-etcd-members
```

> ⚠️ If only 2/3 healthy, **do NOT proceed to next master**. Recover master1 first.

### 2-3. Change Master 2
```bash
vi inventory.ini    # master2 ansible_host=192.168.1.82
make update-ha-ip OLD_IP=192.168.1.72 NEW_IP=192.168.1.82 HOST=master2
sleep 30
make check-etcd-health
```

### 2-4. Change Master 3
```bash
vi inventory.ini    # master3 ansible_host=192.168.1.83
make update-ha-ip OLD_IP=192.168.1.73 NEW_IP=192.168.1.83 HOST=master3
sleep 30
make check-etcd-health
make check-etcd-members
```

### 2-5. Final verification
```bash
kubectl get nodes -o wide
make validate
```

---

## Scenario 3 — HA + domain communication (safest)

When `enable_domain_communication: true` is set, etcd uses hostname-based addressing (`master1.k8s.local`), so IP change requires only `/etc/hosts` updates.

### Procedure
```bash
# 1. Edit inventory.ini (each master's ansible_host to new IP)
vi inventory.ini

# 2. Re-deploy /etc/hosts (all nodes)
make tag-etc-hosts

# 3. Restart kubelet on each master
ansible masters -i inventory.ini -m systemd -a "name=kubelet state=restarted"

# 4. Verify
sleep 30
make check-etcd-health
make validate
```

This approach skips etcd member URL change entirely — much safer and faster.

---

## Verification

```bash
# 1. Node state
kubectl get nodes -o wide
# Confirm INTERNAL-IP is the new IP

# 2. etcd health
make check-etcd-health
make check-etcd-members
# All endpoints have new IP

# 3. Pods healthy
make check-cluster
make validate

# 4. kubeconfig works
kubectl cluster-info
```

## Rollback

Recover via auto-generated `.bak` files.

### Single master
```bash
ssh master1
# Find backup files
ls /etc/kubernetes/manifests/*.bak
ls /etc/kubernetes/*.conf.bak

# Restore
sudo cp /etc/kubernetes/manifests/etcd.yaml.bak /etc/kubernetes/manifests/etcd.yaml
sudo cp /etc/kubernetes/manifests/kube-apiserver.yaml.bak /etc/kubernetes/manifests/kube-apiserver.yaml
# ... and other files

# Restart kubelet
sudo systemctl restart kubelet
```

Or revert inventory to OLD_IP and re-run `make update-ip OLD_IP=<NEW_IP> NEW_IP=<OLD_IP> HOST=master1`.

### HA cluster (etcd quorum damaged)
```bash
# 1. Restore etcd snapshot (from 2-1 backup)
ssh master1 "sudo ETCDCTL_API=3 etcdctl snapshot restore /var/lib/etcd-backup-pre-ip-change.db ..."
# Refer to etcd official docs for full procedure

# 2. Restart all masters
ansible masters -i inventory.ini -m systemd -a "name=kubelet state=restarted"
```

## FAQ

### Q1. After IP change, `kubectl` doesn't work.
A. `~/.kube/config` is updated, but the user's home `~/.kube/config` may need refresh:
```bash
ssh master1
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
kubectl cluster-info
```

### Q2. etcd quorum broke during `update-ha-ip`.
A. Immediately:
1. `make check-etcd-health` — get exact state
2. Don't touch unchanged masters
3. Restore `.bak` files on the master you tried to change
4. Strongly consider switching to domain communication (Scenario 3)

### Q3. master2/master3 can't find master1 with the new IP.
A. Verify `/etc/hosts` is synced across all nodes:
```bash
make tag-etc-hosts
ansible all -i inventory.ini -m shell -a "grep master1 /etc/hosts"
```

### Q4. How do I check if IP is in cert SAN?
```bash
ssh master1 "sudo openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text | grep -A 1 'Subject Alternative Name'"
# If you see "IP Address: 192.168.1.41", use update-ip-with-certs
```

### Q5. After change, `cilium status` is fine but new Pods have no network.
A. Restart CNI Pod:
```bash
kubectl -n kube-system rollout restart daemonset cilium
# Or
make tag-networking
```

## Related docs

- [03 Cert renewal](./03-cert-renewal.en.md) (`update-ip-with-certs` regenerates certs)
- [05 Incident response § etcd quorum loss](./05-incident-response.en.md)
- `roles/update_node_ip/tasks/etcd_member_update.yml`
- `roles/update_node_ip/tasks/ha_single_master.yml`
- [README.en.md § HA Cluster IP Change](../README.en.md)
