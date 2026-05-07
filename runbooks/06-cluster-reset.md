# 06 — 클러스터 리셋·재배포 / Cluster Reset & Redeploy

> **언어 / Language:** [한국어](./06-cluster-reset.md) · [English](./06-cluster-reset.en.md)
> **위험도 / Risk:** High (비가역) · **소요 시간 / Duration:** 15–60분

## 목적 / Purpose

클러스터를 초기 상태로 되돌린다 (전체 또는 워커만). rook-ceph 같은 stateful 컴포넌트는 사전 정리 단계 포함.

## ⚠️ 데이터 손실 경고

**리셋은 비가역**입니다. 다음 데이터는 모두 삭제됩니다:
- etcd (모든 K8s 리소스 메타데이터)
- PV / PVC (특히 hostPath, local-path-provisioner)
- 컨테이너 이미지 캐시 (`/var/lib/containerd`)
- Pod 로그 (`/var/log/pods`)
- kubelet 상태 (`/var/lib/kubelet`)
- CNI 설정 (`/etc/cni/net.d`)

**다음은 보존됨**:
- NFS 볼륨 (별도 NFS 서버에 있는 경우)
- 외부 DB / 외부 스토리지 (Ceph 외부 클러스터, S3 등)
- Harbor / 외부 레지스트리 이미지

## 사전 백업 체크리스트 / Pre-Reset Backup Checklist

리셋 전 다음을 확인:

- [ ] **etcd 스냅샷** (재구축 시 빠른 복원 가능):
  ```bash
  ssh master1 "sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    snapshot save /var/lib/etcd-pre-reset.db"
  ```

- [ ] **PV 데이터** (필요 시 다른 스토리지로 복사):
  ```bash
  kubectl get pv
  # ReclaimPolicy=Retain 인지 확인
  ```

- [ ] **중요 ConfigMap/Secret 백업**:
  ```bash
  kubectl get cm,secret -A -o yaml > backup-cm-secret.yaml
  ```

- [ ] **사용자 매니페스트 백업**:
  ```bash
  kubectl get all,ingress,pvc -A -o yaml > backup-resources.yaml
  ```

- [ ] **`group_vars/all.yml` 백업** (재설치 시 동일 설정 사용):
  ```bash
  cp group_vars/all.yml /tmp/all.yml.backup
  ```

## 시나리오 1 — 전체 리셋

### 일반 환경 (rook-ceph 없음)

```bash
# 1. 사전 백업 (위 체크리스트)

# 2. 리셋 실행
make reset
# 모든 노드에서 kubeadm reset + /etc/kubernetes/* + /var/lib/kubelet/* + /var/lib/etcd/*  정리

# 또는 리셋 후 재부팅까지
make reset-and-reboot
```

`reset_cluster.yml` 동작:
- `kubeadm reset -f`
- `/etc/kubernetes/`, `/var/lib/kubelet/`, `/var/lib/etcd/` 정리
- iptables 규칙 정리
- CNI 설정 (`/etc/cni/net.d/`) 정리

### Rook-Ceph 사용 환경

K8s API가 살아있을 때 CRD 삭제가 가능하므로 **리셋 전 정리** 필수.

```bash
# 1. group_vars/all.yml 활성화
# enable_rook_ceph_cleanup: true

# 2. rook-ceph 정리 + 클러스터 리셋
make reset-rook-ceph
# 또는 단계별
ansible-playbook -i inventory.ini cleanup-rook-ceph.yml
make reset
```

`cleanup_rook_ceph` role이 CephCluster, CephBlockPool 등 CRD를 안전하게 삭제 → 그 후 `make reset`.

## 시나리오 2 — 워커만 리셋

새 K8s 버전 테스트 등으로 워커만 재설치.

```bash
# 1. 워커 drain (워크로드를 마스터로 임시 이전; 단일 노드 클러스터에 적합)
ansible workers -i inventory.ini -m shell -a "kubectl drain $(hostname) --ignore-daemonsets --delete-emptydir-data"

# 2. 워커만 리셋
make reset-workers

# 3. 인벤토리 그대로 두고 재설치
make install-step1   # 시스템 준비
make install-step2   # K8s join
```

## 시나리오 3 — 특정 노드만 리셋 (재가입 준비)

문제가 있는 단일 노드만 리셋해서 다시 join할 때.

```bash
# 1. 클러스터에서 제거
kubectl drain worker3 --ignore-daemonsets --delete-emptydir-data
kubectl delete node worker3

# 2. 노드만 리셋
ansible-playbook -i inventory.ini reset_cluster.yml --limit worker3

# 3. 재추가
make check-and-add-workers
```

## 검증 / Verification

리셋 후 모든 노드가 깨끗한 상태인지 확인:

```bash
# 1. K8s 컴포넌트 모두 정지
make cmd-all CMD="systemctl status kubelet | head -3"
# expected: Active: inactive (dead)

make cmd-all CMD="systemctl status containerd | head -3"
# expected: Active: active (containerd 자체는 동작; K8s만 빠짐)

# 2. K8s 디렉토리 정리됨
make cmd-all CMD="ls /etc/kubernetes/ 2>&1 | head -5"
# expected: 디렉토리 없음 또는 거의 비어있음

# 3. 컨테이너 정리됨
make cmd-all CMD="crictl ps -a"
# expected: 거의 비어있음

# 4. iptables 정리됨
make cmd-masters CMD="iptables -t nat -L KUBE-SERVICES 2>&1 | head -3"
# expected: 'No chain' 또는 빈 chain
```

## 롤백 / Rollback

**리셋은 비가역**이므로 진정한 의미의 롤백은 없음. 단, 다음 옵션:

### 옵션 1: 사전 etcd 스냅샷으로 빠른 재구축
```bash
# 1. 클러스터 재설치
make install

# 2. etcd 데이터 복원 (master1에서)
ssh master1
sudo systemctl stop kubelet
sudo ETCDCTL_API=3 etcdctl snapshot restore /var/lib/etcd-pre-reset.db --data-dir=/var/lib/etcd-restore
sudo mv /var/lib/etcd /var/lib/etcd.new
sudo mv /var/lib/etcd-restore /var/lib/etcd
sudo systemctl start kubelet
```

### 옵션 2: 매니페스트 백업으로 워크로드 재배포
```bash
# 새 클러스터 설치 후
kubectl apply -f backup-resources.yaml
kubectl apply -f backup-cm-secret.yaml
```

### 옵션 3: Git 코드 자체 복구 (설정 변경이 문제였을 때)
```bash
git tag -l "backup/*"
# backup/pre-doc-refresh-20260507
git reset --hard backup/pre-doc-refresh-20260507
```

## 자주 묻는 질문 / FAQ

### Q1. `make reset` 후 다시 `make install` 하니 실패합니다.
A. 가장 흔한 원인:
- iptables 잔존 규칙 → `sudo iptables -F && sudo iptables -t nat -F && sudo iptables -X`
- containerd 컨테이너 잔존 → `sudo crictl rm -af && sudo systemctl restart containerd`
- 그래도 실패 시 `make reset-and-reboot`으로 재부팅

### Q2. PV가 Retain이라 데이터는 살아있는데 어떻게 새 클러스터에 연결하나요?
A. PV 매니페스트만 다시 apply하고, claimRef 제거:
```bash
kubectl get pv <pv-name> -o yaml > pv.yaml
# pv.yaml에서 spec.claimRef 섹션 삭제 → 다시 apply
kubectl apply -f pv.yaml
```

### Q3. Rook-Ceph 정리 안 하고 `make reset` 했어요.
A. CRD finalizer가 남아 있으면 K8s API 살릴 때까지 정리 안 됨. 두 가지 옵션:
1. 새 클러스터 설치 후 같은 디스크로 rook-ceph 재배포 (Ceph는 disk header 보고 기존 클러스터 인식)
2. 디스크 직접 wipe: `sudo dd if=/dev/zero of=/dev/sdb bs=1M count=100`

### Q4. 워커만 리셋 후 재가입했는데 GPU 인식이 안 됩니다.
A. NVIDIA 드라이버는 리셋과 무관하게 보존되지만, containerd 설정은 리셋되므로 NVIDIA 런타임 재설정 필요:
```bash
make tag-nvidia --limit worker3
# 또는
make configure-gpu-full
```

### Q5. 리셋 후 `/etc/kubernetes/`가 그대로 남아있습니다.
A. role이 `kubeadm reset` 후 추가 정리하지만, 권한 문제로 일부 파일이 남을 수 있음:
```bash
ssh worker3 "sudo rm -rf /etc/kubernetes/* /var/lib/kubelet/* /var/lib/etcd/*"
```

## 관련 문서 / Related docs

- [01 Day-0 설치](./01-day0-install.md) — 리셋 후 재설치
- [05 장애 대응](./05-incident-response.md)
- `cleanup-rook-ceph.yml`, `roles/cleanup_rook_ceph/`
- `reset_cluster.yml`, `roles/reset_k8s_cluster/`
