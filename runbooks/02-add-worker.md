# 02 — Worker 노드 추가/제거 / Add or Remove Worker

> **언어 / Language:** [한국어](./02-add-worker.md) · [English](./02-add-worker.en.md)
> **위험도 / Risk:** Medium · **소요 시간 / Duration:** 15–30분

## 목적 / Purpose

기존 클러스터에 신규 Worker 노드 추가, 또는 기존 Worker 안전하게 제거.

## 사전 조건 / Preconditions

- [ ] 기존 클러스터 정상 (`make check-cluster`)
- [ ] **추가 시**: 신규 노드 OS 설치, SSH 키 배포, `inventory.ini` 갱신
- [ ] **제거 시**: 해당 노드 워크로드 다른 노드에 충분한 자원

## Worker 추가

### 방법 1 — 자동 감지 (권장)
```bash
# 1. inventory.ini에 신규 워커 추가
vi inventory.ini
# [workers]
# worker3 ansible_host=192.168.1.43

# 2. 자동 감지 + join
make check-and-add-workers
```

`check-and-add-workers.yml`이 인벤토리와 `kubectl get nodes`를 비교하여 미등록 노드만 자동 join합니다.

### 방법 2 — 수동 추가
```bash
# inventory.ini에 추가 후
make add-workers
# 또는 특정 호스트만
ansible-playbook -i inventory.ini add-worker.yml --limit worker3
```

### 방법 3 — kubeadm 직접 사용
```bash
make get-join-command
# 출력 예: kubeadm join 192.168.1.31:6443 --token abc.xyz --discovery-token-ca-cert-hash sha256:...

ssh worker3
sudo <join-command>
```

### 검증
```bash
make check-workers
# 또는
kubectl get nodes -o wide
# worker3   Ready   <none>   2m   v1.34.1   192.168.1.43

make validate
```

성공 시 worker3가 `Ready` 상태로 표시되어야 함 (CNI Pod 배포 후 1-2분 소요).

## Worker 제거

### 절차 (안전한 drain → delete)

#### 1. 워크로드 이전
```bash
# 노드를 unschedulable로 표시
kubectl cordon worker3

# Pod을 다른 노드로 이전 (drain)
kubectl drain worker3 \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=120 \
  --timeout=300s
```

`--ignore-daemonsets`: kube-proxy, CNI 등은 자동 재생성되므로 무시.

#### 2. 클러스터에서 제거
```bash
kubectl delete node worker3
```

#### 3. 노드 자체 reset (재사용 시)
```bash
# 해당 노드를 inventory.ini에서 제거 후
make reset-workers --limit worker3
# 또는 직접
ssh worker3 "sudo kubeadm reset -f"
ssh worker3 "sudo rm -rf /etc/cni/net.d /var/lib/cni/ /var/lib/kubelet/*"
```

### 검증
```bash
kubectl get nodes
# worker3가 목록에서 제거됨

make check-cluster
```

## 자주 묻는 질문 / FAQ

### Q1. join token이 만료되었어요.
A. token은 기본 24시간 유효. 새로 발급:
```bash
make get-join-command
# 또는
ssh master1 "sudo kubeadm token create --print-join-command"
```

### Q2. `make check-and-add-workers`가 모든 워커를 다시 join하려고 합니다.
A. inventory의 hostname과 클러스터의 node 이름이 다른 경우 발생.
```bash
# 클러스터의 노드 이름 확인
kubectl get nodes
# inventory.ini와 동일한 hostname인지 확인
```
inventory의 `ansible_hostname` 또는 `set_hostname_from_inventory: true` 일관성 확인.

### Q3. drain이 멈춥니다 (PDB 또는 emptyDir 때문).
A.
- PDB 충돌: `kubectl get pdb` → 일시적으로 PDB 완화
- emptyDir 데이터: `--delete-emptydir-data` 추가 (위 명령에 포함됨)
- 영구 멈춤: `kubectl drain --force` (단, RC/Job 외 단독 Pod이 삭제됨)

### Q4. 신규 노드가 NotReady로 머무릅니다.
A. CNI Pod이 도달했는지 확인:
```bash
kubectl -n kube-flannel get pods -o wide   # Flannel
# 또는
kubectl -n kube-system get pods -l k8s-app=cilium -o wide
```
`worker3`에 해당하는 Pod이 있고 Running이면 1-2분 더 대기. CrashLoop이면 → [05 장애 대응 § CNI 장애](./05-incident-response.md).

### Q5. 같은 hostname의 노드를 다시 추가하려는데 거부됩니다.
A. `kubectl delete node` 후 노드의 `/var/lib/kubelet`, `/etc/kubernetes`, `/etc/cni/net.d`까지 정리되어야 깨끗히 재추가 가능. `make reset-workers --limit <host>` 권장.

## 관련 문서 / Related docs

- [`ADD-WORKER-GUIDE.md`](../ADD-WORKER-GUIDE.md) — 상세 (legacy detail 보존용)
- [05 장애 대응](./05-incident-response.md)
- [06 클러스터 리셋](./06-cluster-reset.md)
