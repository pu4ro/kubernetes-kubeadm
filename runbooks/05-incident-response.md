# 05 — 장애 대응 / Incident Response

> **언어 / Language:** [한국어](./05-incident-response.md) · [English](./05-incident-response.en.md)
> **위험도 / Risk:** varies (시나리오별) · **소요 시간 / Duration:** 즉시 / immediate

## 목적 / Purpose

운영 중 클러스터에서 발생하는 일반 장애의 진단 → 원인 → 해결 절차. 증상으로 빠르게 검색 → 시나리오 섹션으로 이동.

## 빠른 검색 / Quick Lookup

| 증상 | 섹션 | 위험도 |
|---|---|---|
| 노드가 `NotReady` | [노드 NotReady](#노드-notready) | Medium |
| HA에서 API 응답 없음 / `kubectl` 멈춤 | [etcd 쿼럼 상실](#etcd-쿼럼-상실) | High |
| Pod가 `ContainerCreating` 멈춤 | [CNI 장애 (Flannel)](#cni-장애-flannel) / [CNI 장애 (Cilium)](#cni-장애-cilium) | Medium |
| `ErrImagePull` / `ImagePullBackOff` | [이미지 pull 실패](#이미지-pull-실패) | Low–Medium |
| `kubectl` 인증 거부 (OIDC 후) | [OIDC 인증 실패](#oidc-인증-실패) | Medium |
| 외부 레지스트리 미러 응답 없음 | [Registry mirror 장애](#registry-mirror-장애) | Medium |

---

## 노드 NotReady

### 증상
```bash
kubectl get nodes
# NAME      STATUS     ROLES           AGE   VERSION
# worker1   NotReady   <none>          12m   v1.34.1
```

### 진단 (1분)
```bash
# 1. kubelet 상태
ssh worker1 "sudo systemctl status kubelet"

# 2. kubelet 로그 마지막 100줄
ssh worker1 "sudo journalctl -u kubelet -n 100 --no-pager"

# 3. CNI 상태 (대부분 NotReady의 원인)
kubectl describe node worker1 | grep -A 5 Conditions

# 4. CNI Pod (Flannel/Cilium)
kubectl get pods -n kube-flannel -o wide       # Flannel
kubectl get pods -n kube-system -l k8s-app=cilium -o wide   # Cilium
```

### 원인 → 해결

**원인 1: containerd 다운**
```bash
ssh worker1 "sudo systemctl status containerd"
# Active: failed (Result: exit-code) ...

# 해결
ssh worker1 "sudo systemctl start containerd && sudo systemctl status containerd"
# 또는 재설정
make tag-container --limit worker1
```

**원인 2: swap이 켜짐**
```bash
ssh worker1 "swapon --show"
# (출력 있음 = swap on)

# 해결
ssh worker1 "sudo swapoff -a"
ssh worker1 "sudo sed -i '/swap/s/^/#/' /etc/fstab"
# 또는
make tag-sysctl --limit worker1
```

**원인 3: CNI 미설치 또는 손상**
```bash
# CNI Pod이 0/1 / CrashLoopBackOff인 경우
kubectl get pods -n kube-flannel
# 또는
kubectl get pods -n kube-system -l k8s-app=cilium

# 해결: CNI 재설치
make tag-networking
```

**원인 4: 이미지 pull 실패** → [이미지 pull 실패](#이미지-pull-실패) 참조

### 검증
```bash
kubectl get nodes
# 모든 노드 Ready
make validate
```

---

## etcd 쿼럼 상실

### 증상
- `kubectl` 명령이 멈춤 / 타임아웃
- HA 클러스터에서 마스터 일부 재시작 후 발생
- API 서버 로그: `etcdserver: request timed out`

### 진단 (위험도 High — 천천히)
```bash
# 1. etcd 헬스체크
make check-etcd-health
# 정상이면 모든 endpoint health=true. 일부만 false면 쿼럼 위험.

# 2. 멤버 목록
make check-etcd-members

# 3. 마스터별 etcd 컨테이너 상태
ansible masters -i inventory.ini -m shell -a "crictl ps | grep etcd"
```

### 원인 → 해결

**원인 1: 마스터 1개 다운 (2/3 정상)**
- 쿼럼 유지됨 → 클러스터 정상 동작 (잠깐 느릴 수 있음)
- 다운된 마스터 복구 시도:
  ```bash
  ssh master2 "sudo systemctl status kubelet containerd"
  # 필요 시 재시작
  ssh master2 "sudo systemctl restart kubelet"
  ```

**원인 2: 마스터 2개 이상 다운 (쿼럼 상실)**
- 매우 위험 — 데이터 손실 가능
- **etcd 백업이 있으면** 단일 노드로 복구:
  ```bash
  # master1에서
  ssh master1 "sudo ETCDCTL_API=3 etcdctl snapshot restore /var/lib/etcd-backup/snapshot.db ..."
  # 자세한 절차는 etcd 공식 문서 참조
  ```
- 백업이 없으면: 클러스터 재구축 + PV 데이터로 복원이 가장 빠를 수 있음 → [06 클러스터 리셋](./06-cluster-reset.md)

**원인 3: IP 변경 후 멤버 URL 미동기화**
- 가장 흔함 — IP 변경 작업 후 자주 발생
- 해결: [04 노드 IP 변경](./04-node-ip-change.md) HA 절차 정확히 따랐는지 확인
- `roles/update_node_ip/tasks/etcd_member_update.yml` 재실행

### 검증
```bash
make check-etcd-health   # 3/3 healthy
kubectl get cs           # ComponentStatuses (deprecated이지만 유용)
```

---

## CNI 장애 (Flannel)

### 증상
- Pod이 `ContainerCreating`에서 멈춤
- `kubectl describe pod` 이벤트: `failed to set up sandbox container ... network: ...`

### 진단
```bash
kubectl get pods -n kube-flannel -o wide
kubectl logs -n kube-flannel -l app=flannel --tail=50
```

### 원인 → 해결

**원인 1: Flannel DaemonSet Pod CrashLoop**
```bash
kubectl describe pod -n kube-flannel <flannel-pod>
# Events: ... ImagePullBackOff
```
→ 이미지 pull 실패. [이미지 pull 실패](#이미지-pull-실패) 절 참조.

**원인 2: pod_subnet 불일치**
- `group_vars/all.yml`의 `pod_subnet`과 Flannel ConfigMap의 `Network`가 다른 경우.
- 해결: `kubectl get cm kube-flannel-cfg -n kube-flannel -o yaml`로 확인 후 일치시키거나 재설치:
  ```bash
  make tag-networking
  ```

**원인 3: `net.bridge.bridge-nf-call-iptables` 미설정**
```bash
ssh worker1 "sysctl net.bridge.bridge-nf-call-iptables"
# net.bridge.bridge-nf-call-iptables = 0 (잘못됨)
make tag-sysctl
```

---

## CNI 장애 (Cilium)

### 진단
```bash
# Cilium CLI (master1에서)
ssh master1
cilium status                           # 전체 상태
cilium connectivity test --quick        # 연결성 테스트

# 또는 Pod 상태
kubectl -n kube-system get pods -l k8s-app=cilium -o wide
```

### 원인 → 해결

**원인 1: cilium-agent CrashLoopBackOff**
```bash
kubectl -n kube-system describe pod <cilium-agent-pod>
kubectl -n kube-system logs <cilium-agent-pod>
```
- 가장 흔함: 이미지 pull 실패 → `cilium_image_repository` 확인
- 또는 kernel 호환성 문제 (구 커널) → `uname -r` 확인 (≥5.4 권장)

**원인 2: Hubble이 시작 안 됨**
```bash
cilium hubble enable
cilium status --wait
```

**원인 3: kube-proxy 대체 (strict 모드) 충돌**
- `cilium_kube_proxy_replacement: strict`인데 `kube-proxy`가 살아있을 때
- 해결: kube-proxy DaemonSet 삭제
  ```bash
  kubectl -n kube-system delete daemonset kube-proxy
  ```

### 검증
```bash
cilium status
make validate
```

---

## 이미지 pull 실패

### 증상
- `kubectl get pods` → `ErrImagePull` / `ImagePullBackOff`
- `kubectl describe pod`: `Failed to pull image: ... 401 Unauthorized` 또는 `i/o timeout`

### 진단
```bash
# 1. 이벤트 자세히
kubectl describe pod <pod>

# 2. 노드에서 직접 pull 테스트
ssh worker1
sudo nerdctl pull harbor.example.com/library/nginx:latest
# 또는 crictl
sudo crictl pull harbor.example.com/library/nginx:latest

# 3. containerd 인증 설정
sudo cat /etc/containerd/config.toml | grep -A 10 registry
sudo ls /etc/containerd/certs.d/
sudo cat /etc/containerd/certs.d/<host>/hosts.toml
```

### 원인 → 해결

**원인 1: 자격증명 오류 (401/403)**
```yaml
# group_vars/all.yml 확인
docker_registries:
  - registry: "harbor.example.com"
    username: "<correct-username>"
    password: "<correct-password>"
```
→ `make tag-docker-credentials` 재실행

**원인 2: CA 신뢰 부족 (self-signed Harbor)**
```yaml
enable_ca_certificates: true
ca_certificates:
  - name: "harbor-ca"
    url: "https://harbor.example.com/ca.crt"
```
→ `make tag-ca-certificates` 또는 `make tag-docker-credentials`

**원인 3: 레지스트리 미러 설정 오류**
```bash
# hosts.toml 확인
ssh worker1 "sudo cat /etc/containerd/certs.d/docker.io/hosts.toml"
# server = "https://docker.io"
# [host."https://harbor.example.com/v2/docker-io"]
#   capabilities = ["pull", "resolve"]
```
→ 매핑 누락 시 `registry_mirror_mappings`에 추가 후 `make tag-registry-mirror`

**원인 4: 네트워크 차단**
- 격리 환경에서 외부 registry 접근 시 발생
- 해결: `enable_registry_mirror: true` + 사내 Harbor 사용

### 검증
```bash
kubectl get pods -A | grep -v Running | grep -v Completed
# 빈 출력이면 모두 정상
```

---

## Registry mirror 장애

### 증상
- 모든 노드에서 외부 이미지 pull 갑자기 실패
- `harbor.example.com` 자체 다운

### 진단
```bash
# Harbor 자체 헬스체크 (별도 인프라)
curl -s https://harbor.example.com/api/v2.0/health

# 노드에서 hosts.toml 동작 확인
ssh worker1
sudo crictl pull docker.io/library/busybox:1.36
# 미러로 우회되는지 확인
sudo journalctl -u containerd | grep -i pull | tail -20
```

### 원인 → 해결

**원인 1: 사내 Harbor 다운 → 임시 폴백**
```bash
# 모든 노드에서 임시로 미러 비활성화
ansible all -i inventory.ini -m shell -a "sudo mv /etc/containerd/certs.d /etc/containerd/certs.d.disabled"
ansible all -i inventory.ini -m systemd -a "name=containerd state=restarted"

# Harbor 복구 후 원복
ansible all -i inventory.ini -m shell -a "sudo mv /etc/containerd/certs.d.disabled /etc/containerd/certs.d"
ansible all -i inventory.ini -m systemd -a "name=containerd state=restarted"
```

**원인 2: hosts.toml 자격증명 만료**
- `registry_mirror_password` 회전 후 → `make tag-registry-mirror` 재실행

---

## OIDC 인증 실패

### 증상
- `kubectl` 명령에 `Unauthorized` / `error: You must be logged in to the server`
- OIDC 활성화 직후

### 진단
```bash
# 1. API 서버 로그
ssh master1 "kubectl -n kube-system logs kube-apiserver-master1 | grep -i oidc"

# 2. API 서버 manifest의 OIDC 플래그
ssh master1 "sudo grep oidc /etc/kubernetes/manifests/kube-apiserver.yaml"

# 3. JWKS 엔드포인트 연결성
ssh master1 "curl -k https://keycloak.example.com/realms/example/.well-known/openid-configuration"
```

### 원인 → 해결

**원인 1: OIDC 설정 적용 후 API 서버 시작 실패**
- 백업 파일로 즉시 롤백:
  ```bash
  ssh master1
  sudo ls /etc/kubernetes/kube-apiserver.yaml.backup-*
  sudo cp /etc/kubernetes/kube-apiserver.yaml.backup-<latest-epoch> /etc/kubernetes/manifests/kube-apiserver.yaml
  # kubelet이 자동으로 Pod 재시작
  ```

**원인 2: IdP 인증서 신뢰 부족**
```yaml
# group_vars/all.yml
oidc_ca_file: "/etc/kubernetes/pki/idp-ca.crt"
```
→ 마스터에 CA 파일 사전 배치 후 `make tag-oidc-apiserver`

**원인 3: groups_claim 잘못됨**
- `oidc_groups_claim`이 IdP가 발급하는 JWT의 실제 claim과 불일치
- IdP 토큰 디코딩 (jwt.io) → 실제 claim 이름 확인

### 롤백 (긴급)
```bash
# 모든 마스터에서 OIDC 비활성화
ansible masters -i inventory.ini -m shell \
  -a "sudo cp /etc/kubernetes/kube-apiserver.yaml.backup-* /etc/kubernetes/manifests/kube-apiserver.yaml"
# 인증서 자동 인증으로 복귀
```

---

## FAQ

### Q1. `kubectl get nodes`가 모두 NotReady인데 어디부터?
A. 90% containerd 또는 CNI 문제. 순서:
1. `ssh master1 "sudo systemctl status containerd"`
2. `kubectl get pods -A | grep -v Running`
3. CNI Pod 로그 확인

### Q2. 한 번에 여러 노드가 NotReady. 클러스터 전체가 죽은 건가요?
A. 마스터(API 서버)가 살아있으면 워커 NotReady는 복구 가능. 먼저:
```bash
make check-cluster   # 마스터 응답 확인
make check-etcd-health  # HA: etcd 정상 확인
```
모두 정상이면 워커별 진단 → [노드 NotReady](#노드-notready).

### Q3. 장애 대응 중 무엇을 절대 하면 안 되나요?
A. **etcd 쿼럼 상실 시 마스터를 함부로 재시작하지 마세요.** 2/3에서 1/3으로 떨어지면 복구가 매우 어려워집니다. 먼저 `make check-etcd-health`로 상태 파악 후 행동.

### Q4. 모든 진단을 했는데도 원인을 못 찾겠어요.
A. `make cmd-all CMD="dmesg | tail -50"`, `make cmd-all CMD="df -h"`, `make cmd-all CMD="free -h"`로 OS 레벨 자원·커널 메시지 확인. 자주 간과되는 원인: 디스크 풀, OOM, kernel panic 후 자동 재부팅.

## 관련 문서 / Related docs

- [04 노드 IP 변경](./04-node-ip-change.md)
- [06 클러스터 리셋](./06-cluster-reset.md)
- [README.md § 문제 해결](../README.md)
- `roles/update_node_ip/tasks/etcd_member_update.yml`
- `roles/install_cilium/tasks/main.yml`
