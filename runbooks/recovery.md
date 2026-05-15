# Recovery (High Risk)

데이터/연결성에 영향을 줄 수 있는 장애 대응. *모든 항목*에 롤백 또는 복구 후 검증 절차를 명시합니다. 실행 전 cluster 상태 스냅샷:

```bash
make check-cluster
make check-etcd-health
make check-etcd-members
kubectl get pods -A -o wide > /tmp/snapshot-pods.txt
```

## 노드 NotReady

- **증상:** `kubectl get nodes` 에 `NotReady`.
- **진단:**
  ```bash
  kubectl describe node <node>                       # Conditions 확인
  make cmd-host HOST="<node>" CMD="journalctl -u kubelet -n 50 --no-pager"
  make cmd-host HOST="<node>" CMD="systemctl status containerd"
  make cmd-host HOST="<node>" CMD="ls /etc/cni/net.d/"
  ```
- **흔한 원인 → 조치:**
  - CNI 미설치/충돌 → §CNI 장애.
  - swap 활성 → `make cmd-host HOST="<node>" CMD="swapoff -a && systemctl restart kubelet"`.
  - containerd down → `make cmd-host HOST="<node>" CMD="systemctl start containerd"`.
  - 디스크 풀 → `df -h` 확인 후 `/var/lib/containerd`, `/var/log` 정리.
- **검증:** 노드가 다시 Ready + `make validate`.
- **롤백:** 별도 롤백 없음. 단, 위 조치로 해결 안 되면 노드를 cluster에서 제거 → 재조인 ([daily-ops.md §Worker 제거](./daily-ops.md) → 재추가).

## etcd Quorum 손실 (HA)

- **증상:** `make check-etcd-health` 에서 1~2 멤버 unhealthy / apiserver 502.
- **진단:**
  ```bash
  make check-etcd-members
  make cmd-host HOST="master1" CMD="crictl logs $(crictl ps -q --name etcd | head -1) | tail -50"
  ```
- **조치 (2/3 살아있는 경우):**
  1. 죽은 멤버 ID 확인 (`member list` 출력의 unhealthy 줄).
  2. `make cmd-host HOST="master1" CMD="crictl exec $(crictl ps -q --name etcd | head -1) etcdctl member remove <ID>"`.
  3. 해당 master를 reset 후 재조인.
- **조치 (1/3만 살아있는 경우 = quorum 손실):**
  1. 살아있는 master에서 단일 노드 etcd로 강제 복구: `etcdctl snapshot save` → 복원 후 cluster 재구성. *데이터 손실 위험* — 직전 백업 사용 권장.
  2. 가능하면 cluster 전체를 백업에서 복원 (외부 etcd 스냅샷 사용).
- **검증:** `check-etcd-health` 3 멤버 healthy, `kubectl get cs` 정상.
- **롤백:** 백업된 `/var/lib/etcd/member/snap/db` 로 복원. quorum 손실 후 임의 변경은 *비가역*.

## CNI 장애 — Flannel

- **증상:** Pod `ContainerCreating` 지속, `kubectl logs -n kube-flannel <pod>` 에 에러.
- **진단:**
  ```bash
  kubectl get pods -n kube-flannel -o wide
  kubectl logs -n kube-flannel <pod>
  make cmd-all CMD="ls /etc/cni/net.d/ /opt/cni/bin/"
  ```
- **흔한 원인 → 조치:**
  - `cni0` IP 충돌 → `ip link delete cni0; ip link delete flannel.1` 후 kubelet 재시작.
  - 노드 간 8472/UDP 차단 (VXLAN) → 방화벽/SG에서 열기.
  - DaemonSet image pull 실패 → §Registry/Mirror 장애.
- **검증:** Pod 모두 Running + `make validate`.
- **롤백:** `make tag-networking` 으로 Flannel 매니페스트 재적용 (idempotent).

## CNI 장애 — Cilium

- **증상:** `cilium status` 에 `Down` / Pod 연결성 손실.
- **진단:**
  ```bash
  make cmd-host HOST="master1" CMD="cilium status --wait=false"
  make cmd-host HOST="master1" CMD="cilium connectivity test"
  kubectl logs -n kube-system -l k8s-app=cilium --tail=50
  ```
- **흔한 원인 → 조치:**
  - 오프라인 환경에서 이미지 pull 실패 → `cilium_image_repository` 확인, 미러에 이미지 push.
  - kernel < 4.19 → 지원 안 됨, OS 업그레이드 필요.
  - cilium-operator만 죽음 → `kubectl -n kube-system delete pod -l name=cilium-operator`.
- **검증:** `cilium status` 전부 OK + `make validate`.
- **롤백:** `network_plugin: flannel` 로 되돌리고 `make reset` 후 재설치. *Pod IP 대역도 함께 변경됨에 주의.*

## Registry / Mirror 장애

- **증상:** 신규 Pod `ImagePullBackOff` / `nerdctl pull` 실패.
- **진단:**
  ```bash
  make cmd-host HOST="worker1" CMD="nerdctl pull docker.io/library/busybox:latest"
  make cmd-host HOST="worker1" CMD="cat /etc/containerd/certs.d/docker.io/hosts.toml"
  make cmd-host HOST="worker1" CMD="cat /etc/hosts | grep -E 'registry|harbor'"
  curl -k https://<mirror-host>/v2/                  # 미러 응답 확인
  ```
- **흔한 원인 → 조치:**
  - 미러 호스트 다운 → 임시로 `enable_registry_mirror: false`, 직접 pull 허용 후 `make tag-registry-mirror`.
  - 자격증명 만료 → `group_vars/all.yml`의 `registry_mirror_password` 갱신 → `make tag-docker-credentials` + `make tag-registry-mirror`.
  - `/etc/hosts` 미설정 → `make tag-etc-hosts`.
- **검증:** `crictl pull <known-image>` 성공 + `make validate`.
- **롤백:** 변경 전 미러 설정 복구 → 위 3개 tag 명령 재실행.

## OIDC 인증 실패

- **증상:** `kubectl` 로그인 실패, apiserver 로그에 OIDC 관련 에러.
- **진단:**
  ```bash
  make cmd-host HOST="master1" CMD="crictl logs $(crictl ps -q --name kube-apiserver | head -1) | grep -i oidc | tail -20"
  curl -k https://keycloak.<domain>/realms/<realm>/.well-known/openid-configuration
  make cmd-host HOST="master1" CMD="cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep oidc"
  ```
- **흔한 원인 → 조치:**
  - issuer URL 도달 불가 (DNS/방화벽) → 호스트 명/네트워크 점검.
  - `oidc_ca_file` 미설정에 self-signed → 변수 추가 후 `make tag-oidc-apiserver`.
  - claim 매핑 오류 → IdP에서 token 디버그 후 `oidc_username_claim`/`oidc_groups_claim` 조정.
- **검증:** OIDC 토큰으로 `kubectl auth can-i ...` 성공.
- **롤백:**
  ```bash
  # group_vars/all.yml: enable_oidc_apiserver: false
  make tag-oidc-apiserver                            # apiserver 매니페스트에서 OIDC 옵션 제거
  ```
  → 임시로 admin.conf 기반 인증으로 복귀.

## 전체 cluster reset

- **위험도:** Highest — *모든 K8s 상태가 사라집니다.*
- **사전 백업 체크리스트:**
  - [ ] etcd 스냅샷: `etcdctl snapshot save /tmp/etcd-pre-reset.db`.
  - [ ] PV 데이터: 워크로드별 사전 백업 (rook-ceph 사용 시 `make reset-rook-ceph`를 *먼저* 실행).
  - [ ] `kubectl get ... -A -o yaml` 으로 manifest 전체 백업.
- **절차:**
  ```bash
  # 옵션 1: 전체 (재부팅 포함)
  make reset-and-reboot                       # 데이터 손실 경고 후 진행

  # 옵션 2: workers만
  make reset-workers

  # 옵션 3: rook-ceph 환경
  make reset-rook-ceph                        # 먼저
  make reset                                  # 그 다음
  ```
- **검증 (reset 후 재설치 시):** `make install` → `make validate`.
- **롤백:** 백업 etcd 스냅샷에서 복원. PV 데이터는 워크로드별 복구 필요. *백업이 없으면 비가역.*

## FAQ

- **Q. `make reset`이 "the host is down" 으로 일부 실패.**
  A. 죽은 호스트만 inventory에서 임시 제거 후 재실행. 다시 합칠 때는 해당 호스트 OS 수준에서 `kubeadm reset -f` 수동 실행.

- **Q. etcd 복구 중 `snapshot status` 가 "no such file" 이라고 한다.**
  A. 스냅샷 경로/소유권 확인 (`crictl exec` 컨테이너 내부 경로 vs 호스트 경로). 호스트 경로면 `--data-dir` 명시.

- **Q. recovery 작업 후 Pod가 `Pending`만 가득하다.**
  A. node taint 잔존 가능: `kubectl describe node <n> | grep Taints`. master 단일 노드면 `allow_master_scheduling: true` + `make tag-scheduling`.

- **Q. registry mirror가 죽었을 때 cluster를 임시로 살리는 가장 빠른 방법은?**
  A. `enable_registry_mirror: false` + `enable_official_k8s_repo: true` 임시 전환 후 `make tag-registry-mirror`. 외부 pull이 차단된 환경이라면 임시 미러 띄우거나 사전 캐시된 이미지 활용.
