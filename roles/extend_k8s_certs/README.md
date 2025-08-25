# Kubernetes Certificate Extension Role

This role extends Kubernetes certificates to 10 years validity period, based on the k8s_10y.sh script.

## Description

Kubernetes certificates created by kubeadm have a default validity of 1 year. This role extends the certificates to 10 years (3650 days) to avoid frequent certificate rotation.

## Features

- ✅ Extends API server certificate
- ✅ Extends API server kubelet client certificate
- ✅ Extends front-proxy client certificate
- ✅ Updates kubeconfig files (admin, controller-manager, scheduler, kubelet)
- ✅ Supports Kubernetes v1.30+ with super-admin.conf
- ✅ Automatic backup of existing certificates
- ✅ Supports both Docker and containerd runtimes
- ✅ Automatic restart of Kubernetes components

## Requirements

- Kubernetes cluster installed with kubeadm
- OpenSSL installed on target nodes
- Root or sudo access

## Role Variables

Available variables in `vars/main.yml`:

```yaml
# Certificate validity in days (10 years = 3650 days)
cert_validity_days: 3650

# Certificate extension mode: 'master', 'check'
cert_extend_mode: 'master'

# Container runtime (docker or containerd)
container_runtime: 'containerd'
```

## Dependencies

None

## Example Playbook

```yaml
- name: Extend Kubernetes Certificates
  hosts: masters
  become: yes
  roles:
    - role: extend_k8s_certs
      vars:
        cert_extend_mode: 'master'
        container_runtime: 'containerd'
```

## Usage

### 1. Check current certificate expiration

```yaml
- role: extend_k8s_certs
  vars:
    cert_extend_mode: 'check'
```

### 2. Extend certificates to 10 years

```yaml
- role: extend_k8s_certs
  vars:
    cert_extend_mode: 'master'
```

## What gets updated

```
/etc/kubernetes
├── admin.conf                    # ✅ Updated
├── super-admin.conf              # ✅ Updated (k8s v1.30+)
├── controller-manager.conf       # ✅ Updated
├── scheduler.conf                # ✅ Updated
├── kubelet.conf                  # ✅ Updated
└── pki
    ├── apiserver.crt             # ✅ Extended to 10 years
    ├── apiserver-kubelet-client.crt # ✅ Extended to 10 years
    └── front-proxy-client.crt    # ✅ Extended to 10 years
```

## Safety Features

- Automatic backup of `/etc/kubernetes` before changes
- Creates backups with timestamp: `/etc/kubernetes.backup-YYYY-MM-DD`
- Verification of certificate expiration before and after
- Non-destructive operation with rollback capability

## Tags

You can use tags to run specific parts:

```bash
ansible-playbook -i inventory.ini site.yml --tags k8s-certs
```

## Author

Generated based on k8s_10y.sh script for Kubernetes certificate extension.