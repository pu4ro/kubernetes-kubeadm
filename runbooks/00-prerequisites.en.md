# 00 — Prerequisites

> **Language / 언어:** [한국어](./00-prerequisites.md) · [English](./00-prerequisites.en.md)
> **Risk:** Low · **Duration:** 30–60 min

## Purpose

Required preparation before installing the cluster: control-node setup, SSH keys, inventory, `group_vars/all.yml` customization. After this doc, proceed directly to [01 Day-0 install](./01-day0-install.en.md).

## Preconditions (for this doc itself)

- [ ] OS installed on all nodes (Ubuntu 20.04+ or RHEL/Rocky 8+)
- [ ] Network connectivity between nodes (master-master, master-worker)
- [ ] Internet access (for offline env, prepare internal mirror separately — see [01 Scenario B](./01-day0-install.en.md))
- [ ] SSH access (root or NOPASSWD sudo)

## 1. Control-node (Ansible host) setup

Pick the host where you'll run Ansible playbooks (usually master1 or a separate management node).

### Ubuntu/Debian
```bash
sudo apt update
sudo apt install -y ansible python3-pip sshpass git
```

### RHEL/CentOS
```bash
sudo yum install -y epel-release
sudo yum install -y ansible python3-pip sshpass git
```

### Version check
```bash
ansible --version    # 2.10+ recommended
python3 --version    # 3.6+
```

## 2. SSH key setup

### Generate key (on control node)
```bash
# New key
ssh-keygen -t rsa -b 4096 -C "ansible@kubernetes" -f ~/.ssh/id_rsa
# No passphrase (Enter twice)
```

### Distribute to all target nodes
```bash
# Masters
ssh-copy-id root@192.168.1.31
ssh-copy-id root@192.168.1.32
ssh-copy-id root@192.168.1.33

# Workers
ssh-copy-id root@192.168.1.41
ssh-copy-id root@192.168.1.42
```

### Verify passwordless access
```bash
ssh root@192.168.1.31 "uptime"
# Should print result without prompting for password (for every node)
```

> For temporary password auth, add `ansible_ssh_pass=...` to `inventory.ini` or use `--ask-pass`. Production should use key auth.

## 3. Clone repository

```bash
git clone <repository-url>
cd kubernetes-kubeadm

# Check directory structure
ls -la
# Makefile, site.yml, inventory.ini, group_vars/, roles/, runbooks/, README.md ...
```

## 4. Edit `inventory.ini`

```ini
# inventory.ini

[masters]
master1 ansible_host=192.168.1.31
# master2 ansible_host=192.168.1.32   # uncomment for HA
# master3 ansible_host=192.168.1.33

[workers]
worker1 ansible_host=192.168.1.41
worker2 ansible_host=192.168.1.42

# 'installs' group: nodes where kubectl/admin.conf is placed (usually master1)
[installs]
master1 ansible_host=192.168.1.31

[all:vars]
ansible_user=root                                         # SSH user
ansible_become=true                                       # use sudo
ansible_become_method=sudo
ansible_ssh_common_args='-o StrictHostKeyChecking=no'    # auto-accept fingerprint on first connection
```

### Group meanings

| Group | Meaning | Notes |
|---|---|---|
| `[masters]` | Control plane nodes | 3 for HA (etcd quorum) |
| `[workers]` | Workload nodes | 0 allowed (single-node cluster) |
| `[installs]` | Where `kubectl` + `admin.conf` are placed | Usually master1 |

## 5. Edit `group_vars/all.yml`

⚠️ **Important**: Never create `group_vars/all.yml` from scratch. Always copy from `.example`:

```bash
# Copy from .example (the .yml file with credentials is gitignored)
cp group_vars/all.yml.example group_vars/all.yml

# Edit for your environment
vim group_vars/all.yml
```

`group_vars/all.yml.example` has detailed Korean + English comments for all 110 variables. Read top-to-bottom and edit only what your environment needs.

### Most-frequently-edited variables

```yaml
# ── Environment branch ──
master_ha: false                       # single master vs HA
network_plugin: "flannel"              # CNI choice
allow_master_scheduling: true          # true for single-node

# ── Internet env ──
enable_official_k8s_repo: true         # online
enable_official_containerd_repo: true

# ── Air-gapped env ──
# enable_official_k8s_repo: false      # use internal mirror
# enable_ubuntu_repo: true
# ubuntu_repo_url: "http://mirror.example.com/ubuntu-repo"

# ── Private registry ──
docker_login_required: false           # false if no private registry
# docker_login_required: true          # set true and fill docker_registries
```

Full variable guide: open [`group_vars/all.yml.example`](../group_vars/all.yml.example) directly.

## 6. First connectivity test

```bash
make ping
# Expected:
# master1 | SUCCESS => { "ping": "pong" }
# worker1 | SUCCESS => { "ping": "pong" }
# worker2 | SUCCESS => { "ping": "pong" }
```

> If it fails, see [FAQ Q1](#faq).

## 7. Group connectivity test
```bash
make test-connection
# Pings masters, workers, installs groups separately
```

## 8. Inventory + variable check
```bash
make show-inventory          # inventory tree (hosts + groups)
make show-variables-example  # safe variable file (no credentials)
```

## Backup recommendations

In production, before using the cluster, identify these backup locations:

| Backup target | Location / method | Purpose |
|---|---|---|
| **etcd snapshot** | No `make` target — manual (see 06 runbook) | Restore cluster metadata |
| **`/etc/kubernetes/pki/`** | tar + external storage | Recovery on cert damage |
| **`group_vars/all.yml`** | External storage (gitignored) | Re-deploy with same config |
| **Persistent Volumes** | External NFS / S3 / Ceph (external cluster) | Preserve workload data |
| **Harbor/registry images** | Harbor's own backup | Image preservation in air-gapped |

## Verification

After completing this doc, all the following must succeed before proceeding to [01 Day-0 install](./01-day0-install.en.md):

- [x] `make ping` — all hosts SUCCESS
- [x] `make test-connection` — all groups SUCCESS
- [x] `make show-inventory` — all nodes listed
- [x] `make show-variables-example` — prints `.example` file
- [x] `cat group_vars/all.yml` — exists and is customized (the actual file, not just `.example`)

## FAQ

### Q1. `make ping` fails on some hosts.
A. Most common causes:
- SSH key not distributed → `ssh-copy-id`
- `ansible_host` or `ansible_user` typo in inventory
- Firewall (port 22 blocked)
- Host's hostname differs from inventory_hostname → align with `set_hostname_from_inventory: true`

### Q2. Ansible commands are very slow.
A. Default fact-gathering can be slow. Enable cache (`~/.ansible.cfg`):
```ini
[defaults]
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts_cache
fact_caching_timeout = 86400
```

### Q3. Why shouldn't I commit `group_vars/all.yml` to git?
A. This file commonly holds credentials (registry passwords, etc.). It's protected by `.gitignore`; commits would persist secrets in git history. Gitignored to prevent accidents.

### Q4. How do I configure NTP?
A. Two options (`group_vars/all.yml`):
```yaml
# Option 1: master1 as internal NTP server
use_local_ntp: true
cluster_network: "192.168.0.0/16"

# Option 2: external NTP servers
use_local_ntp: false
external_ntp_servers:
  - "pool.ntp.org"
  - "time.google.com"
```

### Q5. How is SELinux on RHEL handled?
A. `install_os_package` role auto-switches to permissive mode. If your security policy requires enforcing, apply K8s official SELinux policy separately.

## Related docs

- [01 Day-0 install](./01-day0-install.en.md) — next step
- [README.en.md](../README.en.md) — project overview
- [`group_vars/all.yml.example`](../group_vars/all.yml.example) — all variables detailed
- [06 Cluster reset](./06-cluster-reset.en.md) — detailed backup checklist
