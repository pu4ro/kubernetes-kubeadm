# 04 — 노드 IP 변경 / Node IP Change

> **언어 / Language:** [한국어](./04-node-ip-change.md) · [English](./04-node-ip-change.en.md)
> **위험도 / Risk:** High · **소요 시간 / Duration:** 30–90분

## 목적 / Purpose

마스터/워커 노드의 IP가 변경되었을 때 Kubernetes 매니페스트, etcd 멤버 URL, kubeconfig를 자동 업데이트한다.

## 영향 받는 파일

`update_node_ip` role이 수정하는 파일:
- `/etc/kubernetes/manifests/etcd.yaml`
- `/etc/kubernetes/manifests/kube-apiserver.yaml`
- `/etc/kubernetes/manifests/kube-controller-manager.yaml`
- `/etc/kubernetes/manifests/kube-scheduler.yaml`
- `/etc/kubernetes/admin.conf`, `kubelet.conf`, `controller-manager.conf`, `scheduler.conf`
- `/etc/hosts`
- `~/.kube/config`

각 파일은 자동으로 `.bak`로 백업됨.

## 사전 조건 / Preconditions

- [ ] **etcd 백업 권장** (HA 클러스터는 필수)
- [ ] 새 IP가 동일 서브넷 내 미사용 IP 확인
- [ ] DNS 또는 `custom_hosts` 사전 업데이트
- [ ] `make check-cluster` 정상
- [ ] (HA만) `make check-etcd-health` — 변경 전 3/3 정상

## 시나리오 분기

| 시나리오 | 명령 |
|---|---|
| 단일 마스터 (인증서 SAN 미포함) | `make update-ip` |
| 단일 마스터 (인증서 SAN 포함) | `make update-ip-with-certs` |
| HA 다중 마스터 | `make update-ha-ip` (한 번에 1개) |
| HA + 도메인 통신 | `/etc/hosts` 업데이트만 (간소화) |

---

## 시나리오 1 — 단일 마스터

### 1-1. 사전 점검
```bash
make check-cluster
make check-versions

# 현재 IP 확인
ssh master1 "ip addr show ens18"
```

### 1-2. 인벤토리 수정
```ini
# inventory.ini
[masters]
master1 ansible_host=192.168.1.100   # 새 IP
```

### 1-3. IP 변경 실행

#### 인증서 SAN에 IP가 없는 경우
```bash
make update-ip OLD_IP=192.168.1.41 NEW_IP=192.168.1.100 HOST=master1
```

#### 인증서 SAN에 IP가 포함된 경우 (kubeadm init 시 IP가 SAN에 들어감)
```bash
make update-ip-with-certs OLD_IP=192.168.1.41 NEW_IP=192.168.1.100 HOST=master1
```

### 1-4. 검증
```bash
make check-cluster
make validate
ssh master1 "kubectl get nodes -o wide"
```

---

## 시나리오 2 — HA 다중 마스터 (가장 위험, 천천히)

### 핵심 원칙
1. **한 번에 1개 마스터만 변경** (etcd 쿼럼 보호)
2. **변경 후 30초 이상 대기** (etcd 안정화)
3. **`make check-etcd-health`로 2/3 정상 확인 후** 다음 마스터 진행
4. 실패 시 `OLD_IP`로 복구 가능

### 2-1. 변경 전 상태 백업
```bash
make check-etcd-health    # 3/3 정상 확인
make check-etcd-members   # 멤버 목록 보존
make check-cluster

# (선택) etcd 스냅샷
ssh master1 "sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /var/lib/etcd-backup-pre-ip-change.db"
```

### 2-2. Master 1 변경

#### inventory 수정
```bash
vi inventory.ini
# master1 ansible_host=192.168.1.81   # 새 IP
```

#### 실행
```bash
make update-ha-ip OLD_IP=192.168.1.71 NEW_IP=192.168.1.81 HOST=master1
```

`update_node_ip` role 동작:
1. kubelet 중지
2. manifest/conf 파일 IP 치환
3. etcd 멤버 URL 업데이트 (`etcdctl member update`)
4. kubelet 시작
5. `/etc/hosts`, `~/.kube/config` 업데이트

#### 검증
```bash
sleep 30                  # etcd 안정화 대기
make check-etcd-health    # 3/3 정상 확인 (master2, master3 + 새 IP의 master1)
make check-etcd-members
```

> ⚠️ 만약 2/3만 정상이면 **다음 마스터로 진행하지 마세요**. 먼저 master1 복구.

### 2-3. Master 2 변경
```bash
vi inventory.ini    # master2 ansible_host=192.168.1.82
make update-ha-ip OLD_IP=192.168.1.72 NEW_IP=192.168.1.82 HOST=master2
sleep 30
make check-etcd-health
```

### 2-4. Master 3 변경
```bash
vi inventory.ini    # master3 ansible_host=192.168.1.83
make update-ha-ip OLD_IP=192.168.1.73 NEW_IP=192.168.1.83 HOST=master3
sleep 30
make check-etcd-health
make check-etcd-members
```

### 2-5. 최종 검증
```bash
kubectl get nodes -o wide
make validate
```

---

## 시나리오 3 — HA + 도메인 통신 (가장 안전)

`enable_domain_communication: true` 사용 시 etcd가 호스트명 기반(`master1.k8s.local`)으로 통신하므로 IP 변경 시 `/etc/hosts`만 업데이트하면 됨.

### 절차
```bash
# 1. inventory.ini 수정 (각 마스터의 ansible_host를 새 IP로)
vi inventory.ini

# 2. /etc/hosts 재배포 (모든 노드)
make tag-etc-hosts

# 3. 각 마스터에서 kubelet 재시작
ansible masters -i inventory.ini -m systemd -a "name=kubelet state=restarted"

# 4. 검증
sleep 30
make check-etcd-health
make validate
```

이 방식은 etcd 멤버 URL 변경이 불필요해 훨씬 안전·빠름.

---

## 검증 / Verification

```bash
# 1. 노드 상태
kubectl get nodes -o wide
# INTERNAL-IP가 새 IP로 변경되었는지 확인

# 2. etcd 헬스
make check-etcd-health
make check-etcd-members
# 모든 endpoint가 새 IP

# 3. Pod 정상
make check-cluster
make validate

# 4. kubeconfig 동작
kubectl cluster-info
```

## 롤백 / Rollback

자동 백업된 `.bak` 파일로 복구.

### 단일 마스터
```bash
ssh master1
# 백업 파일 확인
ls /etc/kubernetes/manifests/*.bak
ls /etc/kubernetes/*.conf.bak

# 복구
sudo cp /etc/kubernetes/manifests/etcd.yaml.bak /etc/kubernetes/manifests/etcd.yaml
sudo cp /etc/kubernetes/manifests/kube-apiserver.yaml.bak /etc/kubernetes/manifests/kube-apiserver.yaml
# ... 나머지 파일들

# kubelet 재시작
sudo systemctl restart kubelet
```

또는 inventory를 OLD_IP로 되돌린 뒤 `make update-ip OLD_IP=<NEW_IP> NEW_IP=<OLD_IP> HOST=master1` 재실행.

### HA 클러스터 (etcd 쿼럼 손상 시)
```bash
# 1. etcd 스냅샷 복원 (시나리오 2-1에서 백업한 파일)
ssh master1 "sudo ETCDCTL_API=3 etcdctl snapshot restore /var/lib/etcd-backup-pre-ip-change.db ..."
# 자세한 절차는 etcd 공식 문서 참조

# 2. 모든 마스터 재시작
ansible masters -i inventory.ini -m systemd -a "name=kubelet state=restarted"
```

## FAQ

### Q1. IP 변경 후 `kubectl`이 동작 안 함.
A. `~/.kube/config`가 업데이트되었지만 사용자 홈 디렉토리의 `~/.kube/config`는 별도 갱신 필요:
```bash
ssh master1
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
kubectl cluster-info
```

### Q2. `update-ha-ip` 실행 중 etcd 쿼럼이 깨졌어요.
A. 즉시:
1. `make check-etcd-health` — 정확한 상태 파악
2. 변경 안 된 마스터들은 손대지 말 것
3. 변경 시도한 마스터의 `.bak` 파일로 복구
4. 도메인 통신 사용을 강력 권장 (시나리오 3)

### Q3. master2/master3가 새 IP로 변경된 master1을 못 찾음.
A. `/etc/hosts`가 모든 노드에 동기화되었는지:
```bash
make tag-etc-hosts
ansible all -i inventory.ini -m shell -a "grep master1 /etc/hosts"
```

### Q4. 인증서 SAN에 IP가 들어있는지 어떻게 확인?
```bash
ssh master1 "sudo openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text | grep -A 1 'Subject Alternative Name'"
# IP Address: 192.168.1.41 가 있으면 update-ip-with-certs 사용
```

### Q5. 변경 후 `cilium status`가 잘 동작하지만 새 Pod이 네트워크 안 됨.
A. CNI Pod 재시작 필요:
```bash
kubectl -n kube-system rollout restart daemonset cilium
# 또는
make tag-networking
```

## 관련 문서 / Related docs

- [03 인증서 갱신](./03-cert-renewal.md) (`update-ip-with-certs`는 인증서 재생성)
- [05 장애 대응 § etcd 쿼럼 상실](./05-incident-response.md)
- `roles/update_node_ip/tasks/etcd_member_update.yml`
- `roles/update_node_ip/tasks/ha_single_master.yml`
- [README.md § HA 클러스터 IP 변경](../README.md)
