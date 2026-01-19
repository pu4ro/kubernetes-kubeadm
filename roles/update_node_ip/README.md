# Update Node IP Role

Kubernetes 노드의 IP 주소가 변경될 때 관련 설정 파일을 자동으로 업데이트하는 역할입니다.

## 업데이트 대상 파일

### Kubernetes Manifests (`/etc/kubernetes/manifests/`)
- `etcd.yaml`
- `kube-apiserver.yaml`
- `kube-controller-manager.yaml`
- `kube-scheduler.yaml`

### Kubeconfig 파일 (`/etc/kubernetes/`)
- `admin.conf`
- `kubelet.conf`
- `controller-manager.conf`
- `scheduler.conf`

### 기타
- `~/.kube/config`
- `/var/lib/kubelet/config.yaml`
- `/etc/hosts`

## 사용 방법

### 기본 사용법

```bash
# 단일 노드 IP 변경
ansible-playbook -i inventory.ini update-node-ip.yml \
  -e 'old_ip=192.168.1.100' \
  -e 'new_ip=192.168.1.200' \
  --limit master1

# inventory의 ansible_host를 new_ip로 사용
ansible-playbook -i inventory.ini update-node-ip.yml \
  -e 'old_ip=192.168.1.100' \
  --limit master1
```

### 인증서 재생성 포함

```bash
ansible-playbook -i inventory.ini update-node-ip.yml \
  -e 'old_ip=192.168.1.100' \
  -e 'new_ip=192.168.1.200' \
  -e 'regenerate_certs=true' \
  --limit master1
```

### Makefile 사용

```bash
# Makefile에 추가된 명령어
make update-ip OLD_IP=192.168.1.100 NEW_IP=192.168.1.200 HOST=master1
```

## 변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `old_ip` | (필수) | 변경 전 IP 주소 |
| `new_ip` | `ansible_host` | 변경 후 IP 주소 |
| `restart_kubelet` | `true` | 변경 후 kubelet 재시작 여부 |
| `update_etc_hosts` | `true` | /etc/hosts 업데이트 여부 |
| `regenerate_certs` | `false` | 인증서 재생성 여부 |

## 주의사항

1. **단일 마스터 클러스터**: 이 role은 단일 마스터에서 가장 잘 작동합니다.

2. **다중 마스터 클러스터**: 
   - 한 번에 하나의 마스터만 업데이트하세요
   - etcd 클러스터 멤버 업데이트가 필요할 수 있습니다
   - 다른 마스터의 etcd 설정도 업데이트해야 합니다

3. **인증서 SAN**: IP가 인증서 SAN에 포함된 경우 `regenerate_certs=true` 필요

4. **백업**: 변경 전 자동으로 백업 파일 생성 (`.bak` 확장자)

## 문제 해결

### API 서버 접속 불가

```bash
# kubelet 로그 확인
journalctl -u kubelet -f

# etcd 로그 확인
crictl logs $(crictl ps -a | grep etcd | awk '{print $1}')

# 인증서 재생성 시도
ansible-playbook -i inventory.ini update-node-ip.yml \
  -e 'old_ip=OLD' -e 'new_ip=NEW' -e 'regenerate_certs=true'
```

### etcd 클러스터 문제

```bash
# etcd 멤버 확인
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  member list

# etcd 멤버 업데이트 (필요한 경우)
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  member update <MEMBER_ID> --peer-urls=https://<NEW_IP>:2380
```
