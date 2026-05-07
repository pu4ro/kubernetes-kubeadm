# 03 — Certificate Renewal

> **Language / 언어:** [한국어](./03-cert-renewal.md) · [English](./03-cert-renewal.en.md)
> **Risk:** High · **Duration:** 15–30 min

## Purpose

Extend Kubernetes certificates to 10 years or renew them on the standard 1-year cycle. Covers all kubeadm-issued certificates in `/etc/kubernetes/pki/` including etcd certs.

## Risk Level

**High** — API server restart occurs (few seconds of downtime). Cert corruption can halt the cluster, so backups are mandatory.

## Preconditions

- [ ] **Backup `/etc/kubernetes/pki/`** (mandatory)
  ```bash
  ansible masters -i inventory.ini -m shell \
    -a "sudo tar czf /root/pki-backup-$(date +%s).tgz -C /etc/kubernetes pki"
  ```
- [ ] (HA only) `make check-etcd-health` — 3/3 healthy
- [ ] Pre-check expiry:
  ```bash
  ansible masters -i inventory.ini -m shell -a "kubeadm certs check-expiration"
  ```

### Expiry output interpretation
```
CERTIFICATE                EXPIRES                  RESIDUAL TIME   ...
admin.conf                 Apr 15, 2027 12:00 UTC   354d            ...
apiserver                  Apr 15, 2027 12:00 UTC   354d            ...
apiserver-etcd-client      Apr 15, 2027 12:00 UTC   354d            ...
apiserver-kubelet-client   Apr 15, 2027 12:00 UTC   354d            ...
controller-manager.conf    Apr 15, 2027 12:00 UTC   354d            ...
etcd-healthcheck-client    Apr 15, 2027 12:00 UTC   354d            ...
etcd-peer                  Apr 15, 2027 12:00 UTC   354d            ...
etcd-server                Apr 15, 2027 12:00 UTC   354d            ...
front-proxy-client         Apr 15, 2027 12:00 UTC   354d            ...
scheduler.conf             Apr 15, 2027 12:00 UTC   354d            ...
```
All RESIDUAL TIME should be ≥30d. If less, renew immediately.

## Scenario 1 — 10-year extension (`extend_k8s_certs`)

The `extend_k8s_certs` role re-issues certificates with 10-year validity. Recommended for new clusters or periodic renewal.

### Procedure

```bash
# 1. Verify group_vars/all.yml (default)
# extend_k8s_certificates: true

# 2. Run
make tag-certs
# Or
ansible-playbook -i inventory.ini site.yml --tags k8s-certs
```

### Role behavior
1. Backup existing certs in `/etc/kubernetes/pki/` to `.bak`
2. Run `kubeadm certs renew all` per master
3. Auto-restart controller-manager, scheduler, etcd containers (Pod recreation)
4. API server restart (~30s downtime)

### Verify
```bash
ansible masters -i inventory.ini -m shell -a "kubeadm certs check-expiration"
# All RESIDUAL TIME ≈ 3650d (10 years)

make check-cluster
make validate
```

## Scenario 2 — Standard 1-year renewal (`kubeadm certs renew`)

Standard procedure without 10-year extension.

```bash
# Per master (one at a time for safety)
ssh master1 "sudo kubeadm certs renew all"
ssh master1 "sudo systemctl restart kubelet"

# Refresh kubectl auth
ssh master1 "sudo cp /etc/kubernetes/admin.conf ~/.kube/config && sudo chown \$(id -u):\$(id -g) ~/.kube/config"

# Other masters in HA
ssh master2 "sudo kubeadm certs renew all && sudo systemctl restart kubelet"
ssh master3 "sudo kubeadm certs renew all && sudo systemctl restart kubelet"
```

### Worker kubelet certs
Workers auto-rotate when `rotate-certificates: true`. Manual refresh:
```bash
ansible workers -i inventory.ini -m systemd -a "name=kubelet state=restarted"
```

## Verification

```bash
# 1. Expiry on all certs
ansible masters -i inventory.ini -m shell -a "kubeadm certs check-expiration"

# 2. API server responsive
make check-cluster
kubectl get nodes

# 3. 5-step healthcheck
make validate

# 4. (Optional) etcd cert directly
ssh master1 "sudo openssl x509 -in /etc/kubernetes/pki/etcd/server.crt -noout -dates"
```

## Rollback

### Option 1: Auto-backup
`extend_k8s_certs` role creates `.bak` files. If issues arise post-renewal:
```bash
ssh master1
ls /etc/kubernetes/pki/*.bak
sudo cp /etc/kubernetes/pki/apiserver.crt.bak /etc/kubernetes/pki/apiserver.crt
sudo cp /etc/kubernetes/pki/apiserver.key.bak /etc/kubernetes/pki/apiserver.key
# ... and other files
sudo systemctl restart kubelet
```

### Option 2: Pre-staged tar backup
Restore from the `pki-backup-*.tgz` you created:
```bash
ssh master1
sudo tar xzf /root/pki-backup-<timestamp>.tgz -C /etc/kubernetes
sudo systemctl restart kubelet
```

### Option 3: Cluster damaged → rebuild
If cert recovery fails: [06 Cluster reset](./06-cluster-reset.en.md).

## FAQ

### Q1. After renewal, `kubectl` doesn't work.
A. `~/.kube/config` also needs the new cert:
```bash
ssh master1
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
kubectl cluster-info
```

### Q2. In HA, will renewing per master break etcd?
A. `kubeadm certs renew all` also renews etcd certs, so it works. Still, do one master at a time and verify with `make check-etcd-health` between each.

### Q3. Can a cluster with already-expired certs be revived?
A. Yes. But if kubelet client certs are expired, kubelet won't start. Steps:
1. SSH to master1
2. `sudo kubeadm certs renew all`
3. `sudo systemctl restart kubelet containerd`
4. Repeat on other masters/workers

### Q4. Do CA certs also need renewal?
A. CA defaults to 10 years (kubeadm default). `kubeadm certs renew all` does NOT renew CA. CA renewal approaches cluster rebuild — plan separately.

### Q5. `extend_k8s_certificates: true` but expiry shows 1 year.
A. Role may not have run. Force:
```bash
make tag-certs
# Verify
make cmd-masters CMD="kubeadm certs check-expiration | head -3"
```

## Related docs

- [04 Node IP change](./04-node-ip-change.en.md) (`update-ip-with-certs`)
- [06 Cluster reset](./06-cluster-reset.en.md)
- `roles/extend_k8s_certs/`
- [kubeadm docs: Certificate Management](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/)
