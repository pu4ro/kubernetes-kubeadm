# Risky Ops (Medium Risk)

cluster 상태를 변경하되 *가역적*인 작업. 각 시나리오에 명시적 롤백 절차를 포함합니다.

## 노드 IP 변경 — 단일 마스터

- **위험도:** Medium (API server 일시 중단, 데이터 보존).
- **사전 점검:**
  ```bash
  make check-cluster
  kubectl get nodes -o wide                  # 현재 IP 확인
  ls /etc/kubernetes/pki/                    # 인증서 백업 위치
  ```
- **절차:**
  1. NIC IP 변경 (OS 수준, 별도 작업).
  2. `make update-ip-with-certs OLD_IP=192.168.1.100 NEW_IP=192.168.1.200 HOST=master1`
     - `update-node-ip.yml` 실행 + 인증서 재생성.
  3. 예상 출력: `TASK [update_node_ip : Restart kubelet] ... changed`.
- **검증:**
  ```bash
  make check-cluster                          # 새 IP로 등록
  make validate
  ```
- **실패 시:** kubelet이 안 올라오면 `journalctl -u kubelet -n 100`. apiserver 응답 없음이면 → [recovery.md §노드 NotReady](./recovery.md).
- **롤백:**
  ```bash
  # 1) NIC IP를 OLD_IP로 복구
  # 2) /etc/kubernetes/pki/ 백업이 있다면 복구
  make cmd-host HOST="master1" CMD="systemctl restart kubelet"
  ```

## 노드 IP 변경 — HA (3-마스터 순차)

- **위험도:** Medium-High (다른 2 마스터 정상 시 진행). 한 번에 한 master만.
- **사전 점검:** `make check-etcd-health` → 3 멤버 모두 healthy.
- **절차 (1 master씩 반복):**
  ```bash
  make update-ha-ip-with-certs OLD_IP=... NEW_IP=... HOST=master2
  make check-etcd-health                      # 진행 후 매번 확인
  make check-etcd-members
  ```
- **검증:** 3 master 모두 변경 후 `make validate`.
- **실패 시:** etcd 멤버가 빠지면 → [recovery.md §etcd quorum 손실](./recovery.md).
- **롤백:** 변경 직후 NIC IP 원복 + `update-ha-ip-with-certs`에서 사용한 백업 인증서로 복구. 다른 2 master가 살아있는 한 가역적.

## 인증서 갱신 (10년 연장)

- **위험도:** Medium (apiserver 짧은 재시작).
- **사전 점검:**
  ```bash
  make cmd-masters CMD="kubeadm certs check-expiration"
  ```
- **절차:**
  ```bash
  # group_vars/all.yml에 extend_k8s_certificates: true 확인
  make tag-certs                              # 5–10분
  ```
- **검증:** `kubeadm certs check-expiration` 에서 모든 항목 `> 8y` 표기.
- **실패 시:** 갱신 후 apiserver 응답 없음 → 백업(`/etc/kubernetes/pki/*.bak`) 복구. kubelet client cert 갱신은 자동.
- **롤백:**
  ```bash
  make cmd-masters CMD="cp -a /etc/kubernetes/pki.bak/* /etc/kubernetes/pki/ && systemctl restart kubelet"
  ```

## 표준 1년 인증서 갱신

- **위험도:** Medium.
- **절차:**
  ```bash
  make cmd-masters CMD="kubeadm certs renew all"
  make cmd-masters CMD="systemctl restart kubelet"
  make cmd-masters CMD="crictl ps --name kube-apiserver -q | xargs -r crictl stop"   # control-plane Pod 재시작
  ```
- **검증:** `kubeadm certs check-expiration` 모든 항목 ~1y.
- **롤백:** 위 §10년 연장과 동일 백업/복구.

## 오프라인 → 온라인 전환 (또는 역방향)

- **위험도:** Medium (이미지 pull 출처 변경).
- **사전 점검:** `nerdctl pull <test-image>` 가 새 출처에서 성공하는지 1개 호스트 사전 테스트.
- **절차:**
  ```bash
  # group_vars/all.yml 수정:
  #   온라인 → enable_official_k8s_repo: true, enable_registry_mirror: false
  #   오프라인 → enable_registry_mirror: true + registry_mirror_* 설정
  make tag-registry-mirror                    # mirror 설정 갱신
  make tag-docker-credentials                 # 인증 갱신
  make tag-coredns                            # registry_hosts → CoreDNS 반영
  ```
- **검증:** `make cmd-all CMD="crictl pull <known-image>"` 모든 호스트 성공 + `make validate`.
- **실패 시:** → [recovery.md §Registry/Mirror 장애](./recovery.md).
- **롤백:** 변경 전 `group_vars/all.yml` 값으로 되돌린 후 위 3개 tag 명령 재실행. containerd config는 idempotent하게 재작성됨.

## containerd 데이터 디스크 마운트 (`enable_containerd_disk: true`)

- **위험도:** Medium-High (대상 디스크가 *포맷*됨).
- **사전 점검:**
  ```bash
  make cmd-all CMD="lsblk -f"                 # 디스크 존재 + 빈 디스크 확인
  ```
- **절차:**
  ```bash
  # group_vars/all.yml: enable_containerd_disk: true + containerd_disk_device, fstype 설정
  make tag-setup-containerd-disk
  ```
- **검증:** `make cmd-all CMD="mount | grep /var/lib/containerd"` 모두 새 마운트.
- **실패 시:** 잘못된 디바이스 지정 → 즉시 중단, 데이터 복구 시도. 디바이스 잘못 지정 시 복구 불가하므로 사전 점검 필수.
- **롤백:** fstab에서 해당 라인 삭제 → umount → 이전 상태로 컨테이너 재시작. *디스크에 이미 데이터가 있었다면 복구 불가.*

## FAQ

- **Q. update-ha-ip를 3 master에 한꺼번에 돌려도 되나?**
  A. **금지.** etcd quorum이 깨집니다. 반드시 1대씩 순차.

- **Q. tag-certs 후 apiserver가 응답 없음.**
  A. `crictl ps --name kube-apiserver -q | xargs crictl stop` 으로 강제 재시작. 그래도 안 되면 백업 복구.

- **Q. 오프라인 환경에서 `cilium_offline_install: true` 인데 Cilium Pod 가 CrashLoopBackOff.**
  A. `cilium_image_repository` 설정 확인 + 해당 미러에 이미지 사전 push. → [recovery.md §CNI 장애 (Cilium)](./recovery.md).
