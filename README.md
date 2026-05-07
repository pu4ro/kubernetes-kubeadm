# Kubernetes 클러스터 자동 설치 (Ansible)

> **언어 / Language:** [한국어](./README.md) · [English](./README.en.md)

Ansible을 사용한 Kubernetes 클러스터 자동 배포 도구. Flannel/Cilium CNI, HA, OIDC 인증, 레지스트리 미러, GPU, 오프라인 설치 등 운영 환경 기능을 모두 지원합니다.

## 📋 목차

- [개요](#개요)
- [📂 문서 맵](#-문서-맵)
- [호환성 매트릭스](#호환성-매트릭스)
- [시스템 요구사항](#시스템-요구사항)
- [빠른 시작](#빠른-시작) (단일 / 오프라인 / HA)
- [CNI 선택 (Flannel vs Cilium)](#cni-선택-flannel-vs-cilium)
- [설정 (group_vars/all.yml)](#설정-group_varsallyml)
- [신규 기능 섹션](#신규-기능-섹션)
  - [OIDC 인증](#oidc-인증)
  - [Registry Mirror](#registry-mirror)
  - [사용자 CA 인증서](#사용자-ca-인증서)
  - [전용 Containerd 디스크](#전용-containerd-디스크)
  - [GPU 자동 설정](#gpu-자동-설정)
  - [클러스터 검증 (`validation.yml`)](#클러스터-검증-validationyml)
- [Makefile 명령어](#makefile-명령어)
- [Ansible Tags](#ansible-tags)
- [Runbook 링크](#runbook-링크)
- [문제 해결](#문제-해결)
- [HA 클러스터 IP 변경](#ha-클러스터-ip-변경)
- [추가 리소스](#추가-리소스)

## 개요

이 Ansible 플레이북은 다음을 포함한 Kubernetes 클러스터를 자동 배포합니다:

- **Kubernetes 코어**: 1.27.x – 1.34.x 지원 (kubeadm v1beta3 ↔ v1beta4 자동 분기)
- **컨테이너 런타임**: containerd 1.7.x – 2.2.x (config v2 ↔ v3 자동 감지)
- **CNI 플러그인**: Flannel 또는 Cilium 선택, **오프라인 Cilium 설치 지원**
- **시스템 준비**: OS 패키지, 커널 모듈, sysctl, NTP 설정
- **레지스트리 인증**: containerd 네이티브 (`/etc/containerd/certs.d`) + nerdctl login
- **레지스트리 미러**: 외부 레지스트리(docker.io, quay.io 등) 내부 미러로 자동 우회
- **OIDC 인증**: kube-apiserver + 외부 IdP (Keycloak 등) 통합
- **고가용성**: kube-vip 또는 도메인 기반 HA, Multi-master
- **GPU 지원**: NVIDIA 드라이버 자동 설치, containerd 런타임 설정, 노드 자동 라벨링
- **사용자 CA 인증서**: 시스템 신뢰 저장소에 자동 설치 (3가지 입력 방식)
- **전용 디스크**: containerd 데이터를 별도 디스크에 격리 (선택)
- **인증서 관리**: 1년 표준 또는 10년 자동 연장
- **클러스터 검증**: 5단계 자동 헬스체크 (`make validate`)
- **크로스 플랫폼**: Ubuntu 20.04+, RHEL/Rocky/CentOS 8+
- **오프라인 설치**: APT/YUM 사내 미러, Cilium 사전 다운로드 지원

## 📂 문서 맵

| 목적 | 문서 |
|---|---|
| **빠른 시작** | 이 README의 [빠른 시작](#빠른-시작) 섹션 |
| **모든 변수 상세 설명** | [`group_vars/all.yml.example`](./group_vars/all.yml.example) (변수당 10줄 주석, 이중언어) |
| **운영 시나리오 (설치/IP변경/장애대응 등)** | [`runbooks/`](./runbooks/README.md) ([인덱스](./runbooks/README.md)) |
| **Worker 추가 상세** | [`runbooks/02-add-worker.md`](./runbooks/02-add-worker.md) (legacy: [`ADD-WORKER-GUIDE.md`](./ADD-WORKER-GUIDE.md)) |
| **Containerd 데이터 디렉토리 커스터마이징** | [`CONTAINERD-CUSTOM-PATH.md`](./CONTAINERD-CUSTOM-PATH.md) (legacy detail) |
| **Makefile target 상세 설명** | [`MAKEFILE-GUIDE.md`](./MAKEFILE-GUIDE.md) (legacy detail) |
| **레거시 설치 가이드** | [`k8s-setup-README.md`](./k8s-setup-README.md) (legacy — 신규 절차는 [`runbooks/01-day0-install.md`](./runbooks/01-day0-install.md)) |

## 호환성 매트릭스

| 컴포넌트 | 지원 범위 | 테스트된 기본값 | 비고 |
|---|---|---|---|
| **Kubernetes** | 1.27.x – 1.34.x | `1.34.1` | ≤1.30 → kubeadm v1beta3, ≥1.31 → v1beta4 (자동 분기) |
| **containerd** | 1.7.x – 2.2.x | `2.2.0` | <2.2 → config v2, ≥2.2 → config v3 (자동 감지) |
| **CNI** | Flannel, Cilium 1.15.x | `flannel` | `network_plugin` 변수로 선택 |
| **OS (Ubuntu)** | 20.04 LTS, 22.04 LTS, 24.04 LTS | 22.04 | |
| **OS (RHEL/Rocky/CentOS)** | 8.x, 9.x | 8.x | |
| **kube-vip** | 0.7.x+ | latest | HA + VIP 사용 시 |
| **OIDC IdP** | 표준 OIDC 호환 | Keycloak 23+ | 선택 |

> **버전 변경 방법**: `group_vars/all.yml`에서 `kubernetes_version: "1.27.14"` 또는 `containerd_version: "1.7.6"` 등으로 설정. 모든 K8s 1.27.x – 1.34.x 버전이 동일한 플레이북에서 동작합니다.

## 시스템 요구사항

### 최소 하드웨어 요구사항

| 구성 요소 | Master 노드 | Worker 노드 |
|-----------|-------------|-------------|
| **CPU** | 2 코어 | 2 코어 |
| **메모리** | 4GB RAM | 2GB RAM |
| **스토리지** | 50GB SSD | 30GB SSD |
| **네트워크** | 1Gbps | 1Gbps |

### 권장 프로덕션 환경

| 구성 요소 | Master 노드 | Worker 노드 |
|-----------|-------------|-------------|
| **CPU** | 4+ 코어 | 2+ 코어 |
| **메모리** | 8+ GB RAM | 4+ GB RAM |
| **스토리지** | 100+ GB SSD | 50+ GB SSD |
| **네트워크** | 1Gbps+ | 1Gbps+ |

### 필수 포트

| 포트 | 프로토콜 | 출처 | 용도 |
|------|----------|------|------|
| 6443 | TCP | 전체 | Kubernetes API |
| 2379-2380 | TCP | Master | etcd |
| 10250 | TCP | 전체 | kubelet |
| 10257 | TCP | Master | kube-controller-manager (1.20+) |
| 10259 | TCP | Master | kube-scheduler (1.20+) |
| 8472 | UDP | 전체 | Flannel VXLAN (CNI=flannel) |
| 4240 | TCP | 전체 | Cilium health (CNI=cilium) |
| 4244 | TCP | 전체 | Cilium Hubble (CNI=cilium, optional) |
| 8443 | TCP | Master | kube-vip (HA 사용 시) |

## 빠른 시작

### 사전 요구사항

**제어 노드 설정** (Ansible 실행 노드):

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y ansible python3-pip sshpass

# RHEL/CentOS
sudo yum install -y epel-release
sudo yum install -y ansible python3-pip sshpass
```

**SSH 키 설정**:

```bash
ssh-keygen -t rsa -b 4096 -C "ansible@kubernetes"
ssh-copy-id root@<master-node-ip>
ssh-copy-id root@<worker-node-ip>
ssh root@<node-ip> "uptime"   # 연결 테스트
```

**저장소 클론 + 설정**:

```bash
git clone <repository-url>
cd kubernetes-kubeadm

# 1. 인벤토리 작성
vim inventory.ini

# 2. ⚠️ 변수 파일은 .example을 복사해서 시작 (실제 자격증명을 담은 파일은 .gitignore 처리됨)
cp group_vars/all.yml.example group_vars/all.yml
vim group_vars/all.yml
```

> **첫 사용자 안내**: `group_vars/all.yml.example`에는 110개 변수 모두에 한국어 + 영어 상세 주석이 포함되어 있습니다. 위에서부터 읽으며 자기 환경에 필요한 부분만 수정하면 됩니다.

### 시나리오 A — 단일 마스터 (가장 간단, ~15분)

가장 빠르게 클러스터를 띄우고 싶을 때.

#### 1. 사전 점검
```bash
make ping
# 예상 출력: 모든 호스트 SUCCESS / pong
```
> 실패 시: SSH 키, inventory.ini의 ansible_host/ansible_user 확인.

#### 2. 변수 편집 (`group_vars/all.yml`)
```yaml
master_ha: false                      # 단일 마스터
network_plugin: "flannel"             # 또는 "cilium"
allow_master_scheduling: true         # 단일 노드면 true
enable_domain_communication: false    # 단일 마스터는 불필요
docker_login_required: false          # 사설 레지스트리 미사용 시 false
enable_registry_mirror: false         # 외부 인터넷 직접 사용
```

#### 3. 설치
```bash
make install
# 또는 단계별: make install-step1 && make install-step2 && make install-step3
# 소요: ~15분 (네트워크 + 노드 사양에 따라 다름)
```
> 예상 출력 끝부분:
> ```
> PLAY RECAP *********************************************************************
> master1 : ok=42  changed=18  unreachable=0  failed=0  skipped=5
> ```

#### 4. 검증
```bash
make validate
# 5단계 검증: 노드 Ready / kube-system Pod / DNS / Pod-to-Pod / 외부 연결
# 예상 출력 끝부분:
#   "  Cluster Validation: ALL CHECKS PASSED  "
```
> 실패 시: [`runbooks/05-incident-response.md`](./runbooks/05-incident-response.md) 참조.

### 시나리오 B — 오프라인 설치 (인터넷 차단, ~30분)

격리된 환경에서 설치할 때. 사내 미러 서버 사전 구성 필요.

#### 사전 준비 (인터넷 가능한 별도 호스트에서)
- Ubuntu APT / RHEL YUM 미러 서버 (사내 Apache/Nginx로 호스팅)
- Cilium CLI 사전 다운로드: `cilium-linux-amd64.tar.gz` → `roles/install_cilium/files/`
- 컨테이너 이미지: 사내 Harbor/Registry로 push (`harbor.example.com/external-hub/...`)

#### 변수 편집 (`group_vars/all.yml`)
```yaml
# 오프라인 K8s + containerd 저장소
enable_official_k8s_repo: false
enable_official_containerd_repo: false

# Ubuntu
enable_ubuntu_repo: true
ubuntu_repo_url: "http://mirror.example.com/ubuntu-repo"

# RHEL
enable_rhel_repos: true
rhel_repos:
  - name: "rhel-iso-repo"
    id: "rhel-iso-repo"
    url: "http://mirror.example.com/rhel-repo"
    type: "baseos_appstream"
    enabled: 1
    gpgcheck: 0
    priority: 1

# K8s 컴포넌트 이미지 사내 미러
enable_custom_image_repository: true
k8s_image_repository: "harbor.example.com/external-hub/kubernetes"
coredns_image_repository: "harbor.example.com/external-hub/kubernetes/coredns"
pause_image: "harbor.example.com/external-hub/kubernetes/pause:3.10"

# Cilium (사용 시) 오프라인
network_plugin: "cilium"
cilium_offline_install: true
cilium_image_repository: "harbor.example.com/cilium"

# 외부 레지스트리 미러 (선택)
enable_registry_mirror: true
registry_mirror_host: "harbor.example.com"
registry_mirror_user: "<your-username>"
registry_mirror_password: "<your-password>"

# 검증 외부 URL은 사내 호스트로 변경
# (validation.yml 실행 시 외부 google.com 접근이 막혔으면 실패함)
```

> ⚠️ `validation.yml`의 외부 연결 검사는 기본 `http://google.com`을 사용합니다. 격리 환경에서는 `roles/validate_cluster/defaults/main.yml`의 `validation_external_url`을 사내 호스트로 오버라이드하세요. 또는 `make validate` 대신 `make check-cluster`만 사용.

#### 설치 + 검증
```bash
make install
make check-cluster   # 사내 환경에서는 validation의 외부 검사가 실패할 수 있음
```

### 시나리오 C — HA 3-마스터 (~45분)

운영 환경. kube-vip 또는 도메인 기반 HA 선택.

#### 옵션 1: kube-vip (VIP 사용)
```yaml
# group_vars/all.yml
master_ha: true
kube_vip_address: 192.168.1.30        # 미사용 VIP (마스터와 같은 서브넷)
kube_vip_port: 6443
kube_vip_interface: ens18              # 실제 NIC 이름! `ip link show`로 확인
```

#### 옵션 2: 도메인 기반 (외부 LB 또는 단일 IP)
```yaml
# group_vars/all.yml
master_ha: true
enable_domain_communication: true
domain_suffix: "k8s.local"
api_domain: "k8s-api.internal"
# kube_vip_address는 정의하지 않음

# /etc/hosts 또는 외부 DNS에서 api_domain → 첫 마스터(or LB) IP 매핑 필수
custom_hosts:
  "k8s-api.internal": "192.168.1.31"  # 또는 외부 LB IP
```

```ini
# inventory.ini
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

#### 설치 + 검증
```bash
make install               # site.yml은 마스터를 serial:1로 순차 설치 (etcd race 회피)
make check-etcd-health     # HA 전용: 3/3 노드 정상 확인
make check-etcd-members
make validate
```

> 자세한 HA 설치 절차는 [`runbooks/01-day0-install.md`](./runbooks/01-day0-install.md) (시나리오 C) 참조.

## CNI 선택 (Flannel vs Cilium)

`network_plugin` 변수로 선택:

```yaml
# group_vars/all.yml
network_plugin: "flannel"   # 또는 "cilium"
```

### 선택 가이드

| 요구사항 | 권장 |
|---|---|
| **단순한 L3 라우팅, 최소 자원** | Flannel |
| **NetworkPolicy 강제** | Cilium |
| **eBPF 기반 데이터 평면, 관측성 (Hubble)** | Cilium |
| **kube-proxy 대체 (eBPF로)** | Cilium (`cilium_kube_proxy_replacement: strict`) |
| **WireGuard 암호화** | Cilium (`cilium_encryption_enabled: true`) |
| **단순 PoC, 빠른 시작** | Flannel |

### Flannel 설정

```yaml
network_plugin: "flannel"
pod_subnet: 10.244.0.0/16   # Flannel 기본값과 일치
```

### Cilium 설정 (온라인)

```yaml
network_plugin: "cilium"
cilium_version: "1.15.5"
cilium_cli_version: "v0.16.8"
cilium_arch: "amd64"        # 또는 "arm64"
cilium_offline_install: false
```

### Cilium 오프라인 설치

```yaml
network_plugin: "cilium"
cilium_offline_install: true                       # GitHub 다운로드 건너뜀
cilium_image_repository: "harbor.example.com/cilium"  # 내부 미러
```

추가로 `roles/install_cilium/files/cilium-linux-amd64.tar.gz`에 사전 다운로드한 CLI 바이너리 배치 필요.

```bash
# 사전 다운로드 (인터넷 가능한 호스트에서)
curl -LO https://github.com/cilium/cilium-cli/releases/download/v0.16.8/cilium-linux-amd64.tar.gz
mv cilium-linux-amd64.tar.gz roles/install_cilium/files/
```

## 설정 (group_vars/all.yml)

> **상세 변수 설명**은 [`group_vars/all.yml.example`](./group_vars/all.yml.example)에 있습니다 (110개 변수, 변수당 10줄 주석, 이중언어). 이 섹션은 자주 편집하는 변수의 요약입니다.

### 빠른 편집 가이드

```yaml
# ── 1. Kubernetes 기본 ──
kubernetes_version: "1.34.1"          # 1.27.x ~ 1.34.x 지원
dns_domain: cluster.local
service_subnet: 10.96.0.0/12
pod_subnet: 10.244.0.0/16

# ── 2. HA / 도메인 ──
master_ha: true                        # 다중 마스터
# kube_vip_address: 192.168.1.30      # VIP 방식
enable_domain_communication: true     # 도메인 방식
api_domain: "k8s-api.internal"

# ── 3. 컨테이너 런타임 ──
containerd_version: "2.2.0"           # 1.7.x ~ 2.2.x
containerd_data_base_dir: ""          # 비우면 /var/lib/containerd

# ── 4. CNI ──
network_plugin: "flannel"             # 또는 "cilium"

# ── 5. 시스템 ──
set_timezone: Asia/Seoul
set_hostname_from_inventory: true
parallel_execution:
  system_preparation: 0               # 0=병렬, 1=직렬
  package_installation: 0
  kubernetes_installation: 0

# ── 6. 패키지/저장소 ──
enable_ubuntu_repo: false
enable_rhel_repos: false

# ── 7. 인증/보안 ──
docker_login_required: false
docker_registries: []
enable_oidc_apiserver: false
enable_pod_node_selector: false
enable_ca_certificates: false

# ── 8. GPU ──
enable_nvidia_driver_install: false
enable_nvidia_containerd_config: false
enable_gpu_node_labels: true

# ── 9. Registry Mirror ──
enable_registry_mirror: false

# ── 10. 인증서 ──
extend_k8s_certificates: true         # 10년 연장
allow_master_scheduling: true         # 단일 노드는 true

# ── 11. 디스크 ──
enable_containerd_disk: false         # ⚠️ true면 디스크 포맷됨
```

## 신규 기능 섹션

### OIDC 인증

kube-apiserver에 OIDC 인증을 추가하여 Keycloak 등 외부 IdP와 통합합니다. `configure_oidc_apiserver` role이 `/etc/kubernetes/manifests/kube-apiserver.yaml`을 자동 백업 후 수정합니다.

```yaml
enable_oidc_apiserver: true
domain_host: "example.com"                                              # OIDC issuer 베이스 도메인
oidc_client_id: "kubernetes"
oidc_username_claim: "preferred_username"
oidc_groups_claim: "client_roles"
oidc_issuer_url: "https://keycloak.{{ domain_host }}/realms/example"
# oidc_ca_file: "/etc/kubernetes/pki/idp-ca.crt"                         # self-signed IdP일 때
```

```bash
make tag-oidc-apiserver           # OIDC만 적용 (기존 클러스터에 추가)
```

**적용 후**:
- 백업 파일: `/etc/kubernetes/kube-apiserver.yaml.backup-<epoch>`
- API 서버 자동 재시작 (Pod 재생성 ~30초)
- 검증: `kubectl --kubeconfig /etc/kubernetes/admin.conf -n kube-system get pod -l component=kube-apiserver -o yaml | grep oidc-issuer-url`

**롤백**:
```bash
ssh master1
sudo cp /etc/kubernetes/kube-apiserver.yaml.backup-<epoch> /etc/kubernetes/manifests/kube-apiserver.yaml
# kubelet이 자동으로 Pod 재시작
```

자세한 운영 절차는 [`runbooks/05-incident-response.md § OIDC 인증 실패`](./runbooks/05-incident-response.md) 참조.

### Registry Mirror

containerd가 외부 레지스트리(docker.io, quay.io, registry.k8s.io 등) 요청을 사내 미러로 자동 우회합니다. `configure_registry_mirror` role이 `/etc/containerd/certs.d/<host>/hosts.toml`을 자동 생성합니다.

```yaml
enable_registry_mirror: true
registry_mirror_host: "harbor.example.com"
registry_mirror_user: "<your-username>"
registry_mirror_password: "<your-password>"
registry_mirror_path_prefix: ""

registry_mirror_mappings:
  "docker.io": "docker-io"
  "quay.io": "quay-io"
  "ghcr.io": "ghcr-io"
  "nvcr.io": "nvcr-io"
  "registry.k8s.io": "registry-k8s-io"
  # 더 추가
```

```bash
make tag-registry-mirror      # 기존 클러스터에 미러 설정 추가
```

**적용 결과**:
- 모든 외부 레지스트리 pull이 `harbor.example.com/<mapped-name>/<image>`로 우회
- containerd 자동 재시작
- `docker.io`는 특별 처리 (`registry-1.docker.io` 사용)

**검증**:
```bash
ansible all -i inventory.ini -m shell -a "ls /etc/containerd/certs.d/"
ansible all -i inventory.ini -m shell -a "cat /etc/containerd/certs.d/docker.io/hosts.toml"
```

### 사용자 CA 인증서

자체 서명 Harbor / 사내 PKI 등을 시스템 신뢰 저장소에 설치합니다. 3가지 입력 방식 지원:

```yaml
enable_ca_certificates: true
ca_certificates:
  # 방식 1: 인라인 PEM 콘텐츠
  - name: "internal-ca"
    content: |
      -----BEGIN CERTIFICATE-----
      MIIDxTCCAq2g...
      -----END CERTIFICATE-----

  # 방식 2: URL 다운로드
  - name: "harbor-ca"
    url: "https://harbor.example.com/ca.crt"

  # 방식 3: 로컬 파일 복사
  - name: "registry-ca"
    path: "/root/certs/my-ca.crt"
```

```bash
make tag-docker-credentials   # CA + docker-credentials 함께 설치
```

OS별 설치 위치:
- **Debian/Ubuntu**: `/usr/local/share/ca-certificates/<name>.crt` + `update-ca-certificates`
- **RHEL/CentOS**: `/etc/pki/ca-trust/source/anchors/<name>.crt` + `update-ca-trust extract`

### 전용 Containerd 디스크

> ⚠️ **데이터 손실 경고**: `enable_containerd_disk: true`로 설정하면 지정한 디스크가 **포맷**됩니다 (기존 파일시스템이 없을 때만; role은 `force: no`로 안전 장치 있음). 잘못된 디바이스 지정 시 데이터 손실 가능. **반드시 디바이스 경로를 두 번 확인하세요.**

```yaml
enable_containerd_disk: true
containerd_disk_device: "/dev/sdb"             # ⚠️ 비어있는 디스크
containerd_disk_fstype: "xfs"                  # "xfs" | "ext4"
containerd_disk_mount_point: "/var/lib/containerd"
containerd_disk_mount_options: "defaults,noatime"
```

```bash
make tag-setup-containerd-disk    # 사전 디스크 준비 (containerd 설치 전 실행 권장)
# 또는 dry-run으로 확인 먼저
make dry-run
```

role 동작 (13단계):
1. 디바이스 존재 확인
2. 기존 마운트/blkid 확인
3. **기존 FS가 없으면만** 포맷 (`force: no`)
4. UUID로 fstab 항목 추가 (영구 마운트)
5. containerd 재시작

### GPU 자동 설정

세 가지 단계가 분리되어 있어 환경에 맞게 조합 가능합니다.

```yaml
# 1. NVIDIA 드라이버 자동 설치 (.run 파일)
enable_nvidia_driver_install: true
nvidia_driver_version: "570.124.06"
nvidia_driver_download_url: "http://mirror.example.com/nvidia-drivers"

# 2. .run 설치 후 toolkit 경로 보정 (필요 시)
fix_nvidia_toolkit_path: true

# 3. containerd 설정에 NVIDIA 런타임 추가
enable_nvidia_containerd_config: true

# 4. GPU 노드 자동 라벨링 (gpu=on)
enable_gpu_node_labels: true   # 기본 true
```

```bash
make configure-gpu-full         # 위 4단계를 한 번에 실행
make check-nvidia-gpu           # GPU 감지 확인 (lspci)
make check-nvidia-driver        # 드라이버 설치 상태 확인
```

GPU 워크로드 스케줄링 예시:
```yaml
spec:
  nodeSelector:
    gpu: "on"
  containers:
  - name: app
    image: nvidia/cuda:12.0-base
    resources:
      limits:
        nvidia.com/gpu: 1
```

### 클러스터 검증 (`validation.yml`)

설치 후 또는 변경 후 클러스터 종합 헬스체크:

```bash
make validate
```

**5단계 검증**:
1. **Node Status** — 모든 노드 `Ready` 확인
2. **System Pods** — `kube-system` Pod 모두 Running/Completed 확인
3. **DNS Resolution** — busybox Pod에서 `nslookup kubernetes.default`
4. **Pod-to-Pod Communication** — 두 nginx Pod 간 HTTP 200 확인
5. **External Connectivity** — Pod에서 `http://google.com` (또는 `validation_external_url`) 접근

**격리 환경 주의**: 외부 검사는 `roles/validate_cluster/defaults/main.yml`의 `validation_external_url`로 오버라이드:
```yaml
# group_vars/all.yml에 추가
validation_external_url: "http://harbor.example.com/health"
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

실패 시: [`runbooks/05-incident-response.md`](./runbooks/05-incident-response.md) 참조.

## Makefile 명령어

전체 target 목록은 `make help` 또는 [`MAKEFILE-GUIDE.md`](./MAKEFILE-GUIDE.md). 가장 자주 쓰는 것들만 여기에 정리합니다.

### 일반

| 명령 | 설명 | 빈도 |
|---|---|---|
| `make help` | 전체 target 목록 | 자주 |
| `make ping` | 모든 호스트 SSH 연결 테스트 | 자주 |
| `make check-cluster` | 노드 + Pod 상태 확인 | 자주 |
| `make validate` | 5단계 클러스터 검증 | 자주 |
| `make check-versions` | 설치된 버전 확인 | 가끔 |
| `make show-variables-example` | 안전한 변수 파일 출력 (자격증명 제외) | 가끔 |

### 설치

| 명령 | 설명 |
|---|---|
| `make install` | 전체 클러스터 설치 (`site.yml` 전체) |
| `make install-step1` | Phase 1: 시스템 준비 (sysctl + packages + containerd) |
| `make install-step2` | Phase 2: K8s 설치 (kubeadm) |
| `make install-step3` | Phase 3: CNI 플러그인 |
| `make install-all` | step1 → step2 → step3 순차 |
| `make install-minimal` | 최소 구성 |
| `make install-production` | 프로덕션 권장 구성 |

### Tag 기반 부분 적용

| 명령 | 적용 대상 | 자주 쓰는 이유 |
|---|---|---|
| `make tag-sysctl` | 커널 파라미터만 | 신규 노드 동기화 |
| `make tag-packages` | OS 패키지만 | 패키지 업데이트 |
| `make tag-container` | containerd만 | runtime 재설정 |
| `make tag-docker-credentials` | 레지스트리 인증 + CA | 자격증명 갱신 |
| `make tag-kubernetes` | K8s 컴포넌트만 | 인증서/노드 재구성 |
| `make tag-networking` | CNI 재설치 | CNI 변경 |
| `make tag-certs` | 인증서 10년 연장 | 인증서 갱신 |
| `make tag-coredns` | CoreDNS hosts | hosts 동기화 |
| `make tag-oidc-apiserver` | OIDC 설정 추가 | 인증 정책 변경 |
| `make tag-registry-mirror` | 레지스트리 미러 | 미러 추가 |
| `make tag-label-gpu-nodes` | GPU 노드 라벨 | GPU 추가 |

### Worker 노드 관리

```bash
make check-workers              # Worker 상태 확인
make add-workers                # Worker 노드 추가 (수동)
make check-and-add-workers      # 인벤토리 비교 후 자동 감지+추가
make get-join-command           # 새 join 명령 출력
```

### 호스트별 / 명령 실행

```bash
make limit-master               # Master만
make limit-master1              # master1만
make limit-workers              # Worker만

make cmd-all CMD="uptime"
make cmd-masters CMD="kubectl get nodes"
make cmd-workers CMD="free -h"
make cmd-host HOST="master1" CMD="systemctl status kubelet"
```

### IP 변경 / 인증서

```bash
# 단일 마스터 IP 변경
make update-ip OLD_IP=192.168.1.41 NEW_IP=192.168.1.100 HOST=master1
make update-ip-with-certs OLD_IP=... NEW_IP=... HOST=...   # 인증서 SAN 포함

# HA 클러스터 (한 번에 1개 마스터씩)
make update-ha-ip OLD_IP=... NEW_IP=... HOST=master1
make check-etcd-health
make check-etcd-members
```

### 리셋 / 정리

```bash
make reset                      # 전체 클러스터 초기화 (⚠️ 데이터 손실)
make reset-workers              # Worker만 초기화
make reset-and-reboot           # 리셋 후 재부팅
make reset-rook-ceph            # rook-ceph 사전 정리
```

### 로컬 레지스트리 / NFS

```bash
make registry-init / registry-start / registry-stop / registry-status
make nfs-init / nfs-install / nfs-start / nfs-status / nfs-show-exports
```

### 사내 저장소 (오프라인 환경)

```bash
make ubuntu-repo-init / ubuntu-repo-setup / ubuntu-repo-status
make rhel-repo-init-iso / rhel-repo-setup-directory
make apache-repo-install / apache-repo-status
make httpd-repo-install-iso / httpd-repo-status
```

## Ansible Tags

### Phase별 주요 tag

| Phase | Tag | 적용 대상 |
|---|---|---|
| 1. 시스템 준비 | `base`, `sysctl`, `packages`, `set-hostname`, `etc-hosts` | 모든 노드 |
| 1. 컨테이너 | `container`, `containerd-config`, `containerd-binary-install`, `registry-mirror`, `docker-credentials`, `nerdctl-login`, `ca-certificates` | 모든 노드 |
| 1. 저장소 | `rhel-repo`, `ubuntu-repo`, `k8s-official-repo` | 모든 노드 |
| 1. GPU | `nvidia`, `install-nvidia-driver`, `fix-nvidia-toolkit-path`, `gpu` | GPU 노드 |
| 1. 디스크 | `setup-containerd-disk` | 모든 노드 (선택) |
| 2. K8s | `kubernetes`, `cluster` | Master + Worker |
| 3. 네트워크 | `networking`, `flannel`, `cilium` | Master |
| 4. 스케줄링 | `scheduling`, `label-gpu-nodes` | Master |
| 5. 인증서 | `certificates`, `k8s-certs` | Master |
| 6. CoreDNS | `coredns-hosts` | Master |
| 7. OIDC | `oidc-apiserver` | Master |

### 사용 예시

```bash
# Sysctl 설정만
ansible-playbook -i inventory.ini site.yml --tags sysctl

# 시스템 준비 (K8s 제외)
ansible-playbook -i inventory.ini site.yml --tags sysctl,packages,container

# K8s만 재설치
ansible-playbook -i inventory.ini site.yml --tags kubernetes,networking

# 인증서 연장
ansible-playbook -i inventory.ini site.yml --tags k8s-certs

# 여러 tag 조합
ansible-playbook -i inventory.ini site.yml --tags "sysctl,container,kubernetes"

# 특정 호스트만
ansible-playbook -i inventory.ini site.yml --tags kubernetes --limit master1
```

전체 태그 목록: `make list-tags`

## Runbook 링크

운영자가 시나리오별로 따라갈 수 있는 SOP는 [`runbooks/`](./runbooks/README.md):

| # | Runbook | 위험도 | 소요시간 |
|---|---|---|---|
| 00 | [사전 준비](./runbooks/00-prerequisites.md) | Low | 30–60분 |
| 01 | [Day-0 클러스터 설치](./runbooks/01-day0-install.md) (Online / Offline / HA) | Medium | 30–90분 |
| 02 | [Worker 노드 추가/제거](./runbooks/02-add-worker.md) | Medium | 15–30분 |
| 03 | [인증서 갱신](./runbooks/03-cert-renewal.md) (10년 연장 / 1년 갱신) | High | 15–30분 |
| 04 | [노드 IP 변경](./runbooks/04-node-ip-change.md) (단일 / HA) | High | 30–90분 |
| 05 | [장애 대응](./runbooks/05-incident-response.md) (NotReady / etcd / CNI / 레지스트리) | varies | 즉시 |
| 06 | [클러스터 리셋·재배포](./runbooks/06-cluster-reset.md) | High | 15–60분 |

## 문제 해결

### 노드 NotReady

#### 증상
```bash
kubectl get nodes
# NAME      STATUS     ROLES           AGE   VERSION
# master1   NotReady   control-plane   10m   v1.34.1
```

#### 진단
```bash
# kubelet 로그
ssh master1
sudo journalctl -u kubelet -f

# CNI 상태 (Flannel)
kubectl get pods -n kube-flannel
kubectl logs -n kube-flannel -l app=flannel

# CNI 상태 (Cilium)
cilium status
cilium connectivity test
```

#### 자주 발생하는 원인
- **swap이 켜져 있음**: `swapoff -a` (자동 처리되지만 재부팅 후 다시 켜질 수 있음)
- **containerd 미시작**: `systemctl status containerd`
- **CNI 이미지 pull 실패**: 다음 섹션 참조

자세한 절차: [`runbooks/05-incident-response.md § 노드 NotReady`](./runbooks/05-incident-response.md).

### 이미지 pull 실패 (`ErrImagePull` / `ImagePullBackOff`)

#### 진단
```bash
# 이벤트 확인
kubectl describe pod <pod>

# 노드에서 직접 pull 테스트
ssh worker1
sudo nerdctl pull harbor.example.com/library/nginx:latest

# containerd 인증 설정 확인
sudo cat /etc/containerd/config.toml | grep -A 5 registry
sudo ls /etc/containerd/certs.d/
```

#### 해결
- **자격증명 오류**: `group_vars/all.yml`의 `docker_registries` 확인 → `make tag-docker-credentials` 재실행
- **CA 신뢰 부족**: `enable_ca_certificates: true` + `ca_certificates` 추가 → `make tag-ca-certificates`
- **레지스트리 미러 설정 오류**: `make tag-registry-mirror` 재실행, `/etc/containerd/certs.d/` 확인

### Worker join 실패

```bash
make get-join-command
# 또는
ssh master1
sudo kubeadm token create --print-join-command
```

### etcd 쿼럼 상실 (HA)

```bash
make check-etcd-health
make check-etcd-members
```

3/3 정상이 아니면 [`runbooks/05-incident-response.md § etcd 쿼럼 상실`](./runbooks/05-incident-response.md) 참조.

### 원격 명령 실행 (디버깅 용도)

```bash
make cmd-all CMD="systemctl status kubelet"
make cmd-masters CMD="kubectl get nodes"
make cmd-host HOST="worker1" CMD="nerdctl ps"
```

## HA 클러스터 IP 변경

3중화 HA 클러스터에서 마스터 IP를 변경하는 절차입니다. 자세한 시나리오는 [`runbooks/04-node-ip-change.md`](./runbooks/04-node-ip-change.md) 참조.

### 단일 마스터 vs HA 차이점

| 항목 | 단일 마스터 | HA (3중화) |
|------|------------|-----------|
| etcd 처리 | `--force-new-cluster` | `etcdctl member update` |
| 쿼럼 | 불필요 | 2/3 유지 필요 |
| 실행 방식 | 단일 호스트 | 순차적 (한 번에 하나씩) |

### 명령 요약

```bash
# 사전 확인
make check-etcd-health
make check-etcd-members

# === Master 1 변경 ===
vi inventory.ini    # master1 ansible_host=192.168.1.81 (새 IP)
make update-ha-ip OLD_IP=192.168.1.71 NEW_IP=192.168.1.81 HOST=master1
make check-etcd-health      # 2/3 정상 확인 후 다음 master로 진행

# === Master 2 ===
vi inventory.ini
make update-ha-ip OLD_IP=192.168.1.72 NEW_IP=192.168.1.82 HOST=master2
make check-etcd-health

# === Master 3 ===
vi inventory.ini
make update-ha-ip OLD_IP=192.168.1.73 NEW_IP=192.168.1.83 HOST=master3
make check-etcd-health
make check-etcd-members
kubectl get nodes
```

### 도메인 통신 사용 시 (권장)

`enable_domain_communication: true` 설정 시 etcd가 호스트명 기반이라 IP 변경 시 `/etc/hosts`만 업데이트됨 → 더 안전·빠름.

### 주의사항

- 각 마스터 변경 후 30초 이상 대기 (etcd 안정화)
- **항상 2/3 마스터가 정상**이어야 다음 변경 진행
- 실패 시 `OLD_IP`로 다시 복구 가능
- IP가 인증서 SAN에 포함된 경우 `update-ha-ip-with-certs` 사용

## 추가 리소스

- [Kubernetes 공식 문서](https://kubernetes.io/ko/docs/)
- [kubectl 치트시트](https://kubernetes.io/ko/docs/reference/kubectl/cheatsheet/)
- [kubeadm 문서](https://kubernetes.io/ko/docs/reference/setup-tools/kubeadm/)
- [Cilium 문서](https://docs.cilium.io/)
- [Flannel 문서](https://github.com/flannel-io/flannel)
- [containerd 문서](https://containerd.io/)
- [Ansible 문서](https://docs.ansible.com/)

## ✨ 주요 특징

- ✅ **완전 자동화**: 한 번의 명령으로 전체 클러스터 배포
- ✅ **버전 호환**: K8s 1.27.x – 1.34.x, containerd 1.7.x – 2.2.x
- ✅ **CNI 선택**: Flannel 또는 Cilium (오프라인 설치 지원)
- ✅ **고가용성**: kube-vip 또는 도메인 기반 HA
- ✅ **OIDC 통합**: kube-apiserver + Keycloak 등 외부 IdP
- ✅ **레지스트리 미러**: 외부 레지스트리 사내 미러 자동 우회
- ✅ **GPU 지원**: 드라이버 자동 설치 + 노드 라벨링
- ✅ **사용자 CA**: 자체 서명 인증서 시스템 신뢰 저장소 설치
- ✅ **인증서 관리**: 10년 자동 연장
- ✅ **클러스터 검증**: 5단계 자동 헬스체크
- ✅ **오프라인 설치**: APT/YUM/Cilium 사내 미러 지원
- ✅ **크로스 플랫폼**: Ubuntu / RHEL / Rocky / CentOS
- ✅ **Worker 자동 추가**: 미등록 노드 자동 감지
- ✅ **Runbook**: 7개 시나리오별 단계별 SOP (KO/EN)

## 기여 / 라이선스

이슈 및 풀 리퀘스트를 환영합니다. MIT License.

---

**Made with ❤️ for Kubernetes Administrators**
