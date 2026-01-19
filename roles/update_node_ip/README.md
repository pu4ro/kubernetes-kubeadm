# Update Node IP Role

Kubernetes 설정 파일의 IP 주소를 변경하는 역할입니다.

> **주의**: 이 role은 파일만 변경합니다. 실제 IP 변경은 사용자가 직접 수행해야 합니다.

## 업데이트 대상 파일

- `/etc/kubernetes/manifests/etcd.yaml`
- `/etc/kubernetes/manifests/kube-apiserver.yaml`
- `/etc/kubernetes/manifests/kube-controller-manager.yaml`
- `/etc/kubernetes/manifests/kube-scheduler.yaml`
- `/etc/kubernetes/admin.conf`
- `/etc/kubernetes/kubelet.conf`
- `/etc/kubernetes/controller-manager.conf`
- `/etc/kubernetes/scheduler.conf`
- `/var/lib/kubelet/config.yaml`
- `/etc/hosts`
- `~/.kube/config`

## 사용법

```bash
# 기본 사용
make update-ip OLD_IP=192.168.1.100 NEW_IP=192.168.1.200 HOST=master1

# 인증서 재생성 포함
make update-ip-with-certs OLD_IP=192.168.1.100 NEW_IP=192.168.1.200 HOST=master1

# Ansible 직접 실행
ansible-playbook -i inventory.ini update-node-ip.yml \
  -e 'old_ip=192.168.1.100' \
  -e 'new_ip=192.168.1.200' \
  --limit master1
```

## 변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `old_ip` | (필수) | 변경 전 IP |
| `new_ip` | `ansible_host` | 변경 후 IP |
| `update_etc_hosts` | `true` | /etc/hosts 업데이트 여부 |
| `regenerate_certs` | `false` | 인증서 재생성 여부 |

## 작업 순서

1. 사용자가 시스템 IP 변경
2. inventory.ini 업데이트
3. 이 role 실행하여 설정 파일 변경
4. kubelet 재시작 (수동)
