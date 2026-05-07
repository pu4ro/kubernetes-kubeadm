# 01 — Day-0 클러스터 설치 / Day-0 Cluster Install

> **언어 / Language:** [한국어](./01-day0-install.md) · [English](./01-day0-install.en.md)
> **위험도 / Risk:** Medium · **소요 시간 / Duration:** 30–90분

## 목적 / Purpose

신규 Kubernetes 클러스터를 처음부터 배포한다. 환경 유형에 따라 3가지 시나리오로 나누어 동일한 4단계 구조 (사전 점검 → 설정 편집 → 실행 → 검증) 로 진행한다.

## 위험도 / Risk Level

**Medium** — 처음 설치는 멱등하므로 실패 시 `make reset` 후 재시도 가능. 다만 기존 클러스터에 `make install`을 다시 실행하면 일부 컴포넌트가 재설치되며 일시적 다운타임 발생 가능.

## 사전 조건 / Preconditions

- [ ] [00 사전 준비](./00-prerequisites.md) 완료 (SSH, inventory, group_vars 편집)
- [ ] 모든 노드가 `make ping` 응답
  ```bash
  make ping
  # 예상: master1 | SUCCESS => { "ping": "pong" }, ...
  ```
- [ ] 호스트당 최소 사양 충족 (마스터 4GB RAM/2core, 워커 2GB/2core)
- [ ] swap이 영구적으로 꺼져 있거나 자동으로 꺼지도록 sysctl 적용 가능 상태
- [ ] 모든 노드 시간 동기화 가능 (NTP 또는 master1을 NTP 서버로)

## 시나리오 A — 단일 마스터 (Online, ~15분)

### A-1. 사전 점검
```bash
make ping                # 모든 호스트 SUCCESS
make test-connection     # 그룹별 ping
make show-inventory      # inventory 트리 확인
```

### A-2. `group_vars/all.yml` 편집
처음이라면 반드시 `cp group_vars/all.yml.example group_vars/all.yml` 후 편집.

```yaml
# 핵심 변경 사항 (단일 마스터 + 인터넷 연결)
master_ha: false
network_plugin: "flannel"             # 또는 "cilium"
allow_master_scheduling: true         # 단일 노드는 true 필수
enable_domain_communication: false
docker_login_required: false
enable_registry_mirror: false
enable_oidc_apiserver: false
extend_k8s_certificates: true
```

### A-3. 실행
```bash
make install
# 또는 단계별 (디버깅 시)
make install-step1   # sysctl + packages + containerd
make install-step2   # K8s (kubeadm init/join)
make install-step3   # CNI 플러그인
```

성공 출력 (마지막):
```
PLAY RECAP *********************************************************************
master1 : ok=42  changed=18  unreachable=0  failed=0  skipped=5
```

### A-4. 검증
```bash
make validate
```
성공 출력:
```
=========================================
  Cluster Validation: ALL CHECKS PASSED
=========================================
  - Node Status:           OK
  - System Pods:           OK
  - DNS Resolution:        OK
  - Pod-to-Pod Comms:      OK
  - External Connectivity: OK
=========================================
```

실패 시 → [05 장애 대응](./05-incident-response.md) 시나리오별 진단.

## 시나리오 B — 오프라인 설치 (Air-gapped, ~30분)

### B-1. 사전 준비 (인터넷 가능한 별도 호스트에서)

1. **사내 미러 서버 준비**: Apache/Nginx로 OS 패키지, K8s 패키지, 컨테이너 이미지 호스팅
2. **Cilium CLI 사전 다운로드** (Cilium 사용 시)
   ```bash
   curl -LO https://github.com/cilium/cilium-cli/releases/download/v0.16.8/cilium-linux-amd64.tar.gz
   mv cilium-linux-amd64.tar.gz roles/install_cilium/files/
   ```
3. **K8s 컨테이너 이미지 사내 push** (`harbor.example.com/external-hub/kubernetes/...`)

### B-2. `group_vars/all.yml` 편집

```yaml
# 사내 저장소
enable_official_k8s_repo: false
enable_official_containerd_repo: false

# Ubuntu 사내 APT
enable_ubuntu_repo: true
ubuntu_repo_url: "http://mirror.example.com/ubuntu-repo"

# RHEL 사내 YUM (다중 가능)
enable_rhel_repos: true
rhel_repos:
  - name: "rhel-iso-repo"
    id: "rhel-iso-repo"
    url: "http://mirror.example.com/rhel-repo"
    type: "baseos_appstream"
    enabled: 1
    gpgcheck: 0
    priority: 1

# K8s 컴포넌트 이미지
enable_custom_image_repository: true
k8s_image_repository: "harbor.example.com/external-hub/kubernetes"
coredns_image_repository: "harbor.example.com/external-hub/kubernetes/coredns"
pause_image: "harbor.example.com/external-hub/kubernetes/pause:3.10"

# Cilium 오프라인
network_plugin: "cilium"
cilium_offline_install: true
cilium_image_repository: "harbor.example.com/cilium"

# 외부 레지스트리 미러
enable_registry_mirror: true
registry_mirror_host: "harbor.example.com"
registry_mirror_user: "<your-username>"
registry_mirror_password: "<your-password>"

# 검증 외부 URL을 사내 호스트로 변경 (구글 차단)
validation_external_url: "http://harbor.example.com/health"
```

### B-3. 실행
```bash
make install
```

### B-4. 검증
```bash
make validate
# 외부 검사가 사내 호스트로 redirect됨 (validation_external_url)
```

또는 외부 검사 제외:
```bash
make check-cluster   # 단순 노드/Pod 상태만
```

## 시나리오 C — HA 3-마스터 (~45분)

### C-1. 사전 점검
```bash
make ping
make show-inventory   # [masters]에 3개 노드 확인
```

### C-2. inventory 작성
```ini
[masters]
master1 ansible_host=192.168.1.31
master2 ansible_host=192.168.1.32
master3 ansible_host=192.168.1.33

[workers]
worker1 ansible_host=192.168.1.41
worker2 ansible_host=192.168.1.42

[installs]
master1 ansible_host=192.168.1.31

[all:vars]
ansible_user=root
ansible_become=true
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

### C-3. `group_vars/all.yml` 편집

#### 옵션 1: kube-vip
```yaml
master_ha: true
kube_vip_address: 192.168.1.30        # 미사용 VIP
kube_vip_port: 6443
kube_vip_interface: ens18              # `ip link show` 로 확인 필수
allow_master_scheduling: false        # 운영은 false
extend_k8s_certificates: true
```

#### 옵션 2: 도메인 기반 (외부 LB)
```yaml
master_ha: true
enable_domain_communication: true
domain_suffix: "k8s.local"
api_domain: "k8s-api.internal"
# kube_vip_address는 정의하지 않음

# DNS 또는 /etc/hosts에 api_domain → 첫 마스터 IP 매핑 필수
custom_hosts:
  "k8s-api.internal": "192.168.1.31"
```

### C-4. 실행
```bash
make install   # site.yml은 마스터를 serial:1로 순차 설치 (etcd race 회피)
```

마스터별 로그가 순차적으로 표시됩니다 (master1 → master2 → master3 → workers 병렬).

### C-5. 검증
```bash
make check-etcd-health      # 3/3 노드 정상
make check-etcd-members     # 멤버 목록
make check-cluster
make validate
```

성공 시 출력 예 (`make check-etcd-health`):
```
{"endpoint": "192.168.1.31:2379", "health": "true"}
{"endpoint": "192.168.1.32:2379", "health": "true"}
{"endpoint": "192.168.1.33:2379", "health": "true"}
```

## 검증 / Verification

```bash
# 1. 클러스터 헬스체크
make validate

# 2. (HA만) etcd
make check-etcd-health
make check-etcd-members

# 3. 버전 확인
make check-versions

# 4. Pod 상세
kubectl get pods -A -o wide
```

## 롤백 / Rollback

설치가 실패했거나 처음부터 다시 시작하고 싶을 때:

```bash
# 전체 클러스터 리셋
make reset

# 또는 워커만
make reset-workers

# 리셋 후 재부팅까지
make reset-and-reboot
```

⚠️ **데이터 손실**: etcd, PV, 컨테이너 이미지 모두 삭제됨. 운영 환경에서 실행 전 [06 클러스터 리셋](./06-cluster-reset.md) 사전 백업 체크리스트 확인.

## 자주 묻는 질문 / FAQ

### Q1. `make install`이 중간에 멈춥니다. 다시 실행해도 되나요?
A. 네, 플레이북은 멱등하게 작성되어 있어 재실행해도 안전합니다. 다만 어디서 멈췄는지 로그 확인 후 → 해당 단계 tag로 부분 실행이 더 빠릅니다 (`make tag-kubernetes` 등).

### Q2. swap이 자동으로 꺼지는데 재부팅 후 다시 켜집니다.
A. `configure_sysctl` role이 `/etc/fstab`의 swap 항목을 주석 처리합니다. 그래도 켜지면:
```bash
ssh <node>
sudo cat /etc/fstab | grep -i swap
sudo systemctl mask swap.target  # 강제 비활성화
```

### Q3. HA에서 master2/master3 join이 실패합니다.
A. 가장 흔한 원인:
- `kube_vip_interface`가 실제 NIC와 다름 → `ip link show`로 확인
- `kube_vip_address`가 이미 사용 중 → 다른 미사용 IP로 변경
- 도메인 통신 사용 시 `api_domain` DNS 미설정 → `custom_hosts` 추가
- 자세히: [05 장애 대응 § etcd 쿼럼 상실](./05-incident-response.md)

### Q4. Cilium 설치 후 `cilium status`가 한참 멈춥니다.
A. `cilium status --wait`은 기본 30회 × 10초 = 5분 대기. 5분 후에도 멈추면:
```bash
ssh master1
kubectl -n kube-system get pods -l k8s-app=cilium
kubectl -n kube-system describe pod <cilium-pod>
```
이미지 pull 실패가 가장 흔함 → `cilium_image_repository` 또는 인터넷 연결 확인.

### Q5. 오프라인 환경에서 `make validate`가 외부 검사에서 실패합니다.
A. `validation.yml`의 외부 검사는 `validation_external_url` (기본 `http://google.com`)로 wget 시도. 격리 환경에서는:
```yaml
# group_vars/all.yml에 추가
validation_external_url: "http://harbor.example.com/health"
```
또는 `make validate` 대신 `make check-cluster`만 사용.

### Q6. 설치 후 `kubectl`이 동작하지 않습니다.
A. master1에서:
```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
kubectl get nodes
```

## 관련 문서 / Related docs

- [00 사전 준비](./00-prerequisites.md)
- [05 장애 대응](./05-incident-response.md)
- [06 클러스터 리셋](./06-cluster-reset.md)
- [README.md](../README.md)
- [`group_vars/all.yml.example`](../group_vars/all.yml.example) — 모든 변수 상세 주석
