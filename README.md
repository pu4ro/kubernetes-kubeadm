# Kubernetes 클러스터 자동 설치 (Ansible)

Ansible을 사용한 Kubernetes 클러스터 자동 배포 도구입니다.

[English](./README.en.md) | 한국어

## 📋 목차

- [개요](#개요)
- [시스템 요구사항](#시스템-요구사항)
- [지원 플랫폼](#지원-플랫폼)
- [빠른 시작](#빠른-시작)
- [설정](#설정)
- [설치](#설치)
- [Makefile 명령어](#makefile-명령어)
- [Ansible Tags](#ansible-tags)
- [설치 후 작업](#설치-후-작업)
- [문제 해결](#문제-해결)
- [추가 기능](#추가-기능)

## 🎯 개요

이 Ansible 플레이북은 다음을 포함한 Kubernetes 클러스터를 자동으로 배포합니다:

- **Kubernetes 코어**: Kubernetes 1.27.14 클러스터 설치
- **컨테이너 런타임**: containerd 구성 (NVIDIA GPU 자동 감지 지원)
- **네트워크 플러그인**: Flannel CNI
- **시스템 준비**: OS 패키지, 커널 모듈, sysctl 설정
- **레지스트리 인증**: Private registry 인증 지원 (containerd 네이티브 설정)
- **고가용성**: Multi-master 구성 지원 (kube-vip)
- **크로스 플랫폼**: Ubuntu 및 RHEL/CentOS 지원
- **로컬 레지스트리**: 독립 실행형 스크립트로 관리

## 💻 시스템 요구사항

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

## 🐧 지원 플랫폼

### 운영체제
- **Ubuntu**: 20.04 LTS, 22.04 LTS, 24.04 LTS (Noble)
- **RHEL/CentOS**: 8.x, 9.x
- **Rocky Linux**: 8.x, 9.x

### Kubernetes 버전
- **기본**: 1.27.14
- **지원**: 1.25.x - 1.28.x

## 🚀 빠른 시작

### 1. 사전 요구사항

**제어 노드 설정** (Ansible 실행 노드):

```bash
# Ansible 설치 (Ubuntu/Debian)
sudo apt update
sudo apt install ansible python3-pip sshpass

# Ansible 설치 (RHEL/CentOS)
sudo yum install epel-release
sudo yum install ansible python3-pip sshpass
```

### 2. SSH 키 설정

```bash
# SSH 키 쌍 생성
ssh-keygen -t rsa -b 4096 -C "ansible@kubernetes"

# 공개 키를 모든 대상 노드에 복사
ssh-copy-id root@<master-node-ip>
ssh-copy-id root@<worker-node-ip>

# 연결 테스트
ssh root@<node-ip> "uptime"
```

### 3. 설치 과정

```bash
# 1. 저장소 클론
git clone <repository-url>
cd kubernetes-kubeadm

# 2. 설정 파일 편집
vim inventory.ini
vim group_vars/all.yml

# 3. 연결 테스트
make ping

# 4. 전체 클러스터 설치
make install

# 또는 Ansible 직접 실행
ansible-playbook -i inventory.ini site.yml
```

## ⚙️ 설정

### 1. 인벤토리 설정

`inventory.ini`를 인프라에 맞게 편집:

```ini
[masters]
master1 ansible_host=192.168.135.31
# master2 ansible_host=192.168.135.32  # HA 구성 시
# master3 ansible_host=192.168.135.33

[workers]
worker1 ansible_host=192.168.135.41
worker2 ansible_host=192.168.135.42

[installs]
master1 ansible_host=192.168.135.31

[all:vars]
ansible_user=root
ansible_become=true
ansible_become_method=sudo
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

### 2. 전역 변수 설정

`group_vars/all.yml`을 환경에 맞게 편집:

```yaml
# Kubernetes 기본 설정
kubernetes_version: '1.27.14'
dns_domain: cluster.local
service_subnet: 10.96.0.0/12
pod_subnet: 10.244.0.0/16

# 컨테이너 런타임
containerd_version: "1.7.6"
containerd_data_base_dir: "/data/containerd"  # 호스트별: /data/containerd/{hostname}

# NVIDIA GPU 지원 (자동 감지)
has_nvidia_gpu: auto  # auto: 자동 감지, true/false: 수동 설정

# 레지스트리 설정
insecure_registries:
  - "harbor.example.com"

# Containerd 레지스트리 인증 (containerd config.toml에 직접 설정)
docker_registries:
  - registry: "harbor.example.com"
    protocol: "https"  # or "http"
    username: "admin"
    password: "Harbor12345"

# 마스터 노드 스케줄링 (단일 노드 클러스터용)
allow_master_scheduling: true

# 인증서 연장
extend_k8s_certificates: true

# CoreDNS 호스트 설정
configure_coredns_hosts: true
registry_hosts:
  "harbor.example.com": "192.168.135.100"
```

## 🔧 Makefile 명령어

프로젝트에 포함된 Makefile로 간편하게 클러스터를 관리할 수 있습니다.

### 일반 명령어

```bash
make help                    # 사용 가능한 모든 명령어 확인
make ping                    # 모든 호스트 연결 테스트
make check-cluster           # 클러스터 상태 확인
```

### 설치 명령어

```bash
make install                 # 전체 클러스터 설치
make install-step1           # Phase 1: 시스템 준비
make install-step2           # Phase 2: Kubernetes 설치
make install-step3           # Phase 3: 네트워크 플러그인
make install-all             # 단계별 전체 설치
make install-minimal         # 최소 구성 설치
make install-production      # 프로덕션 전체 설치
```

### Tag 기반 설치

```bash
make tag-sysctl              # Sysctl 설정
make tag-packages            # OS 패키지 설치
make tag-container           # 컨테이너 런타임
make tag-docker-credentials  # 레지스트리 인증
make tag-kubernetes          # Kubernetes 설치
make tag-networking          # CNI 플러그인
make tag-certs               # 인증서 10년 연장
make tag-coredns             # CoreDNS 설정
make tag-harbor              # Harbor 프로젝트
```

### 호스트별 설치

```bash
make limit-master            # Master 노드만
make limit-workers           # Worker 노드만
make limit-master1           # master1만
```

### Worker 노드 관리

```bash
make check-workers           # Worker 상태 확인
make add-workers             # Worker 노드 추가
make check-and-add-workers   # 자동 감지 후 추가
```

### 커스텀 명령어 실행

```bash
# 모든 호스트에서 명령어 실행 (자세한 출력)
make cmd-all CMD="uptime"
make cmd-all CMD="df -h"

# Master 노드에서만 실행
make cmd-masters CMD="kubectl get nodes"
make cmd-masters CMD="kubectl get pods -A"

# Worker 노드에서만 실행
make cmd-workers CMD="free -h"
make cmd-workers CMD="nerdctl images"

# Installs 노드에서만 실행
make cmd-installs CMD="systemctl status containerd"

# 특정 호스트 지정 실행
make cmd-host HOST="master1" CMD="uptime"
make cmd-host HOST="worker1" CMD="df -h"

# HOST 없이 실행하면 사용 가능한 호스트 목록 표시
make cmd-host
```

### 로컬 레지스트리 관리

로컬 Docker 레지스트리는 Ansible 없이 독립 실행형 스크립트로 관리됩니다.

```bash
# 설정 파일 초기화
make registry-init           # .env.registry 생성

# 레지스트리 관리
make registry-start          # 레지스트리 시작
make registry-stop           # 레지스트리 중지
make registry-restart        # 레지스트리 재시작
make registry-status         # 상태 확인
make registry-logs           # 로그 확인
make registry-remove         # 컨테이너 제거
```

**로컬 레지스트리 설정 (.env.registry)**:
```bash
# 설정 파일 생성
make registry-init

# .env.registry 편집
vim .env.registry

# 레지스트리 시작
make registry-start
```

### 리셋 및 정리

```bash
make reset                   # 전체 클러스터 초기화
make reset-workers           # Worker 노드만 초기화
```

### 유틸리티

```bash
make show-inventory          # 인벤토리 확인
make show-variables          # 전역 변수 확인
make lint                    # 문법 검사
make list-tags               # 사용 가능한 tags
make list-tasks              # 모든 tasks
make dry-run                 # Dry run 모드
make test-connection         # 그룹별 연결 테스트
make get-join-command        # Worker join 명령어
make check-versions          # 설치된 버전 확인
```

## 🏷️ Ansible Tags

### 주요 Phase Tags

| Tag | 설명 | 적용 대상 |
|-----|------|-----------|
| `base`, `sysctl` | Sysctl 및 커널 모듈 설정 | 모든 노드 |
| `base`, `packages` | OS 패키지 설치 | 모든 노드 |
| `container` | 컨테이너 런타임 (containerd) | 모든 노드 |
| `docker-credentials` | 레지스트리 인증 | 모든 노드 |
| `kubernetes`, `cluster` | Kubernetes 설치 | 모든 노드 |
| `networking` | CNI 플러그인 (Flannel) | Master 노드 |
| `scheduling` | Master 스케줄링 허용 | Master 노드 |
| `certificates`, `k8s-certs` | 인증서 10년 연장 | Master 노드 |
| `coredns-hosts` | CoreDNS 호스트 설정 | Master 노드 |
| `harbor-setup` | Harbor 프로젝트 설정 | 모든 노드 |

### 사용 예시

```bash
# Sysctl 설정만
ansible-playbook -i inventory.ini site.yml --tags sysctl

# 시스템 준비 (Kubernetes 제외)
ansible-playbook -i inventory.ini site.yml --tags sysctl,packages,container

# Kubernetes만 설치
ansible-playbook -i inventory.ini site.yml --tags kubernetes,networking

# 인증서 연장
ansible-playbook -i inventory.ini site.yml --tags k8s-certs

# 레지스트리 인증 설정
ansible-playbook -i inventory.ini site.yml --tags docker-credentials

# 여러 tag 조합
ansible-playbook -i inventory.ini site.yml --tags "sysctl,container,kubernetes"

# 특정 호스트만
ansible-playbook -i inventory.ini site.yml --tags kubernetes --limit master1
```

## 🔧 설치 후 작업

### 1. 클러스터 상태 확인

```bash
# Makefile 사용
make check-cluster

# 또는 수동으로
ssh root@<master-ip>
kubectl get nodes -o wide
kubectl get pods -A
kubectl cluster-info
```

### 2. kubectl 설정 (일반 사용자)

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# kubectl alias (자동 설정됨)
k get nodes          # kubectl get nodes
kgp                  # kubectl get pods
kgn                  # kubectl get nodes
```

### 3. 샘플 애플리케이션 배포

```bash
# nginx 배포
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=NodePort

# 서비스 확인
kubectl get svc nginx
NODE_PORT=$(kubectl get svc nginx -o jsonpath='{.spec.ports[0].nodePort}')
curl http://<node-ip>:$NODE_PORT
```

## 🔍 문제 해결

### 일반적인 문제

#### 1. 노드 NotReady 상태

```bash
# kubelet 로그 확인
sudo journalctl -u kubelet -f

# CNI (Flannel) 확인
kubectl get pods -n kube-system | grep flannel
kubectl logs -n kube-system -l app=flannel
```

#### 2. Worker 노드 Join 실패

```bash
# Makefile 사용
make get-join-command

# 또는 수동으로
kubeadm token create --print-join-command
```

#### 3. 레지스트리 인증 문제

```bash
# containerd 설정 확인
sudo cat /etc/containerd/config.toml | grep -A 10 registry

# 이미지 pull 테스트
sudo nerdctl pull harbor.example.com/library/nginx:latest

# kubelet 로그
sudo journalctl -u kubelet -f | grep -i "pull"
```

#### 4. 원격 명령 실행

```bash
# Makefile 사용 (자세한 출력)
make cmd-all CMD="systemctl status kubelet"
make cmd-masters CMD="kubectl get nodes"
make cmd-host HOST="worker1" CMD="nerdctl ps"

# 또는 Ansible 직접 사용
ansible all -i inventory.ini -m shell -a "uptime"
ansible masters -i inventory.ini -m shell -a "kubectl get pods -A"
```

### 필수 포트

| 포트 | 프로토콜 | 출처 | 용도 |
|------|----------|------|------|
| 6443 | TCP | 전체 | Kubernetes API |
| 2379-2380 | TCP | Master | etcd |
| 10250 | TCP | 전체 | kubelet |
| 10251 | TCP | Master | kube-scheduler |
| 10252 | TCP | Master | kube-controller |
| 8472 | UDP | 전체 | Flannel VXLAN |

## 🎯 추가 기능

### 클러스터 초기화

```bash
# Makefile 사용
make reset                   # 전체 클러스터
make reset-workers           # Worker만

# 또는 Ansible 직접 사용
ansible-playbook -i inventory.ini reset_cluster.yml
ansible-playbook -i inventory.ini reset_cluster.yml --limit worker1
```

### Worker 노드 자동 추가

```bash
# 인벤토리에 없는 Worker 자동 감지 및 추가
make check-and-add-workers

# Worker 상태 확인
make check-workers

# 수동으로 Worker 추가
make add-workers
```

### 인증서 10년 연장

```bash
# Makefile 사용
make tag-certs

# 또는 Ansible 직접 사용
ansible-playbook -i inventory.ini site.yml --tags k8s-certs
```

### GPU 지원 (자동 감지)

GPU는 자동으로 감지되며, containerd가 NVIDIA 런타임으로 자동 설정됩니다.

```yaml
# group_vars/all.yml
has_nvidia_gpu: auto  # 자동 감지
# has_nvidia_gpu: true   # 강제 활성화
# has_nvidia_gpu: false  # 비활성화
```

**참고**: NVIDIA driver는 노드에 미리 설치되어 있어야 합니다.

```bash
# GPU 감지 확인
make cmd-all CMD="lspci | grep -i nvidia"

# containerd 설정 확인
make cmd-all CMD="cat /etc/containerd/config.toml | grep nvidia"
```

### 로컬 Docker 레지스트리

독립 실행형 스크립트로 관리되며, `.env.registry` 파일로 설정합니다.

```bash
# 1. 설정 파일 생성
make registry-init

# 2. 설정 편집 (.env.registry)
vim .env.registry
```

**설정 예시 (.env.registry)**:
```bash
REGISTRY_IMAGE=registry:2
REGISTRY_IMAGE_TAR=/root/docker.tar.gz
REGISTRY_CONTAINER_NAME=local-registry
REGISTRY_HOST_PORT=80
REGISTRY_CONTAINER_PORT=5000
REGISTRY_DATA_DIR=/opt/local-registry/data
REGISTRY_ADDITIONAL_ARGS="--env REGISTRY_STORAGE_DELETE_ENABLED=true"
```

```bash
# 3. 레지스트리 시작
make registry-start

# 4. 상태 확인
make registry-status

# 5. 레지스트리 사용
nerdctl push localhost:80/myimage:latest
```

### NFS 서버 구성

NFS 서버도 독립 실행형 스크립트로 관리되며, `.env.nfs` 파일로 설정합니다.

```bash
# 1. 설정 파일 생성
make nfs-init

# 2. 설정 편집 (.env.nfs)
vim .env.nfs
```

**설정 예시 (.env.nfs)**:
```bash
# NFS export 경로 (쉼표로 구분)
NFS_EXPORT_PATHS="/data/nfs/share1,/data/nfs/share2,/opt/kubernetes-storage"

# 각 경로별 export 옵션 (쉼표로 구분, 경로 순서와 동일)
NFS_EXPORT_OPTIONS="*(rw,sync,no_subtree_check,no_root_squash),192.168.0.0/16(rw,sync,no_subtree_check),10.0.0.0/8(rw,sync,no_subtree_check)"

# 디렉토리 소유자 및 권한
NFS_EXPORT_OWNER="root"
NFS_EXPORT_GROUP="root"
NFS_EXPORT_MODE="0777"

# 부팅 시 자동 시작
NFS_ENABLE_ON_BOOT="true"
```

**간단한 예제 (Kubernetes PV용)**:
```bash
# 단일 공유 디렉토리
NFS_EXPORT_PATHS="/data/kubernetes-pvs"
NFS_EXPORT_OPTIONS="*(rw,sync,no_subtree_check,no_root_squash)"
NFS_EXPORT_MODE="0777"
```

**보안 강화 예제**:
```bash
# 특정 서브넷만 허용
NFS_EXPORT_PATHS="/data/secure"
NFS_EXPORT_OPTIONS="192.168.135.0/24(rw,sync,no_subtree_check,root_squash)"
NFS_EXPORT_OWNER="nobody"
NFS_EXPORT_GROUP="nogroup"
NFS_EXPORT_MODE="0755"
```

```bash
# 3. NFS 서버 설치 및 시작
make nfs-install

# 4. 상태 확인
make nfs-status

# 5. exports 확인
make nfs-show-exports

# 6. exports 재로드 (설정 변경 후)
make nfs-reload
```

**Makefile 명령어**:
```bash
make nfs-init          # 설정 파일 초기화
make nfs-install       # NFS 서버 설치 및 시작
make nfs-start         # NFS 서버 시작
make nfs-stop          # NFS 서버 중지
make nfs-restart       # NFS 서버 재시작
make nfs-status        # 상태 확인
make nfs-reload        # exports 재로드
make nfs-show-exports  # /etc/exports 내용 표시
make nfs-add-export    # exports 추가 및 적용
make nfs-remove        # NFS 설정 제거
```

**Kubernetes에서 NFS 사용**:
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteMany
  nfs:
    server: 192.168.135.31  # NFS 서버 IP
    path: /data/kubernetes-pvs
  persistentVolumeReclaimPolicy: Retain
```

### High Availability (HA) 구성

```yaml
# group_vars/all.yml
master_ha: true
kube_vip_address: 192.168.135.30
kube_vip_interface: ens18
```

```ini
# inventory.ini
[masters]
master1 ansible_host=192.168.135.31
master2 ansible_host=192.168.135.32
master3 ansible_host=192.168.135.33
```

### 도메인 기반 통신 (IP 변경 없이 클러스터 구성)

IP 주소를 매번 변경하지 않고 도메인 이름 기반으로 클러스터를 구성할 수 있습니다.

```yaml
# group_vars/all.yml
enable_domain_communication: true     # 도메인 기반 통신 활성화
domain_suffix: "k8s.local"            # 노드 도메인 접미사 (예: master1.k8s.local)
api_domain: "k8s-api.internal"        # API 서버 도메인
```

#### 사용 시나리오

**1. 단일 마스터 + 도메인 기반 통신**
```yaml
# kube_vip_address를 설정하지 않음
enable_domain_communication: true
api_domain: "k8s-api.internal"
```
- `/etc/hosts`에 자동으로 `api_domain -> 첫 번째 마스터 IP` 매핑 추가
- 외부 DNS 서버 설정 시 `api_domain`을 마스터 IP로 해석하도록 구성

**2. HA + kube-vip (기존 방식)**
```yaml
master_ha: true
kube_vip_address: 192.168.135.30    # VIP 설정
enable_domain_communication: true   # 선택적
```
- kube-vip가 VIP를 관리
- `controlPlaneEndpoint`에 VIP 사용

**3. HA + 외부 로드밸런서**
```yaml
master_ha: true
# kube_vip_address는 설정하지 않음
enable_domain_communication: true
api_domain: "k8s-api.internal"
```
- 외부 로드밸런서 구성 필요
- DNS에서 `api_domain`을 로드밸런서 IP로 해석하도록 설정
- `/etc/hosts` 또는 `custom_hosts`로 로드밸런서 IP 매핑:
```yaml
custom_hosts:
  "k8s-api.internal": "192.168.135.100"  # 로드밸런서 IP
```

#### 장점
- 환경 변경 시 IP 주소 수정 불필요
- DNS 기반 유연한 엔드포인트 관리
- VM 마이그레이션, 클라우드 환경에 적합

### Containerd 데이터 디렉토리 커스터마이징

```yaml
# group_vars/all.yml
containerd_data_base_dir: "/data/containerd"  # 호스트별: /data/containerd/{hostname}
```

```bash
# 데이터 디렉토리 확인
make cmd-all CMD="ls -la /data/containerd/"
```

## 📁 프로젝트 구조

```
kubernetes-kubeadm/
├── group_vars/
│   └── all.yml                       # 전역 변수
├── inventory.ini                     # 인벤토리 파일
├── roles/                            # Ansible 역할
│   ├── configure_sysctl/             # Sysctl 설정
│   ├── install_os_package/           # OS 패키지
│   ├── install_containerd/           # 컨테이너 런타임
│   ├── setup-docker-credentials/     # 레지스트리 인증
│   ├── install_kubernetes/           # K8s 설치
│   ├── install_flannel/              # CNI 플러그인
│   ├── extend_k8s_certs/             # 인증서 연장
│   └── configure_coredns_hosts/      # CoreDNS 설정
├── scripts/
│   └── manage-registry.sh            # 로컬 레지스트리 관리 스크립트
├── site.yml                          # 메인 플레이북
├── reset_cluster.yml                 # 클러스터 리셋
├── add-worker.yml                    # Worker 추가
├── check-and-add-workers.yml         # Worker 자동 추가
├── Makefile                          # 편의 명령어
├── .env.registry.example             # 레지스트리 설정 템플릿
└── README.md                         # 이 문서
```

## 📚 추가 리소스

- [Kubernetes 공식 문서](https://kubernetes.io/ko/docs/)
- [kubectl 치트시트](https://kubernetes.io/ko/docs/reference/kubectl/cheatsheet/)
- [Ansible 문서](https://docs.ansible.com/)
- [Flannel 문서](https://github.com/flannel-io/flannel)
- [containerd 문서](https://containerd.io/)

## ✨ 주요 특징

- ✅ **완전 자동화**: 한 번의 명령으로 전체 클러스터 배포
- ✅ **크로스 플랫폼**: Ubuntu/RHEL/CentOS 지원
- ✅ **고가용성**: Multi-master 구성 지원 (kube-vip)
- ✅ **병렬 실행**: 빠른 설치를 위한 병렬 작업
- ✅ **유연한 Tag**: 원하는 구성 요소만 선택 설치
- ✅ **인증서 관리**: 10년 인증서 자동 연장
- ✅ **GPU 지원**: NVIDIA GPU 자동 감지
- ✅ **레지스트리 통합**: containerd 네이티브 인증 설정
- ✅ **로컬 레지스트리**: 독립 실행형 스크립트로 관리
- ✅ **Worker 자동 추가**: 미등록 노드 자동 감지 및 추가
- ✅ **원격 명령 실행**: Makefile을 통한 편리한 원격 명령 실행
- ✅ **Makefile 통합**: 간편한 클러스터 관리 명령어
- ✅ **모듈화**: 재사용 가능한 Ansible 역할

## 🤝 기여

이슈 및 풀 리퀘스트를 환영합니다!

## 📝 라이선스

MIT License

---

**Made with ❤️ for Kubernetes Administrators**
