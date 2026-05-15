# Daily Ops (Low Risk)

idempotent하고 cluster 상태 변경이 없는 일상 운영. 모두 `make validate`로 마무리.

## Worker 추가 (수동)

- **위험도:** Low (조인 실패해도 기존 노드 영향 없음).
- **사전 점검:**
  ```bash
  make ping                       # 신규 호스트 SSH OK
  ansible <new-worker> -i inventory.ini -m setup -a 'filter=ansible_distribution*'
  ```
- **절차:**
  1. `inventory.ini`의 `[workers]`에 신규 호스트 추가.
  2. `make add-workers` 실행 (5–15분).
  3. 예상 출력:
     ```
     PLAY RECAP *********************************************************************
     worker-new : ok=XX  changed=XX  unreachable=0  failed=0
     ```
- **검증:**
  ```bash
  make check-cluster              # 신규 노드가 Ready
  make validate
  ```
- **실패 시:** master에서 `kubeadm token list` → 만료면 `kubeadm token create --print-join-command` 재시도. 그래도 안 되면 → [recovery.md §Worker join 실패](./recovery.md).

## Worker 자동 감지·추가

inventory에는 있는데 cluster에는 없는 노드를 자동으로 조인.

- **위험도:** Low.
- **절차:** `make check-and-add-workers` (5–20분, 호스트 수에 비례).
- **검증:** `make check-workers` (inventory vs cluster 비교 표 출력).

## Worker 제거

- **위험도:** Low (정상 drain 시).
- **사전 점검:** `kubectl get pods -A --field-selector=spec.nodeName=<worker> -o wide` 로 영향 Pod 확인.
- **절차:**
  ```bash
  kubectl drain <worker> --ignore-daemonsets --delete-emptydir-data --timeout=10m
  kubectl delete node <worker>
  # 노드 자체 reset이 필요하면:
  make cmd-host HOST="<worker>" CMD="kubeadm reset -f && rm -rf /etc/cni/net.d"
  # inventory.ini에서 해당 노드 삭제
  ```
- **검증:** `kubectl get nodes` 에서 사라짐 확인 + `make validate`.
- **실패 시:** drain이 PDB(PodDisruptionBudget)에 막히면 `kubectl get pdb -A` 확인 후 임시로 maxUnavailable 조정.

## 노드/Pod 상태 확인

- **위험도:** Low (read-only).
- **명령:**
  ```bash
  make check-cluster              # nodes -o wide + pods -A
  make check-etcd-health          # HA etcd health (master_ha=true)
  make check-etcd-members         # HA etcd member list
  make check-nvidia-gpu           # 모든 노드 lspci | grep nvidia
  make check-nvidia-driver        # nvidia-smi 결과
  ```

## 클러스터 종합 검증 (validation.yml)

- **위험도:** Low (검증만, 변경 없음).
- **명령:** `make validate` (3–10분).
- **검사 항목:** 노드 Ready, kube-system Pod, DNS, Pod-to-Pod, 외부 연결.
- **예상 출력:**
  ```
  TASK [validate_cluster : ✅ All nodes Ready] ************************************
  TASK [validate_cluster : ✅ kube-system Pods Running] ***************************
  TASK [validate_cluster : ✅ CoreDNS resolves cluster.local] *********************
  ```
- **실패 시:** 실패한 task의 항목별로 [recovery.md](./recovery.md) 참조.

## 특정 호스트에서 명령 실행

진단·작은 변경에 유용. *변경* 명령은 가능하면 Ansible role로 재사용.

```bash
make cmd-host  HOST="master1" CMD="kubectl top nodes"
make cmd-all   CMD="df -h | grep /var/lib"
make cmd-masters CMD="systemctl status kubelet | head -5"
```

- **위험도:** 명령 자체에 의존. read-only는 Low, mutating은 Medium 이상으로 간주.

## FAQ

- **Q. `make add-workers`가 "node already exists" 로 실패한다.**
  A. inventory에는 있는데 cluster에 부분 등록된 노드. 해당 호스트에서 `kubeadm reset -f` 후 재시도. 또는 `make check-and-add-workers` 사용.

- **Q. `make validate` 가 DNS 실패만 빨갛게 뜬다.**
  A. CoreDNS Pod 상태 확인 (`kubectl -n kube-system get pods -l k8s-app=kube-dns`). `enable_registry_mirror=true`인데 미러가 죽었을 가능성 → [recovery.md §Registry/Mirror 장애](./recovery.md).

- **Q. 노드 라벨이 사라졌다 (예: gpu=on).**
  A. `make tag-label-gpu-nodes` 재실행. idempotent.
