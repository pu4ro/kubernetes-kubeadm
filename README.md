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
- [Ansible Tags](#ansible-tags)
- [설치 후 작업](#설치-후-작업)
- [문제 해결](#문제-해결)
- [추가 기능](#추가-기능)

## 🎯 개요

이 Ansible 플레이북은 다음을 포함한 Kubernetes 클러스터를 자동으로 배포합니다:

- **Kubernetes 코어**: Kubernetes 1.27.14 클러스터 설치
- **컨테이너 런타임**: containerd 구성
- **네트워크 플러그인**: Flannel CNI
- **시스템 준비**: OS 패키지, 커널 모듈, 방화벽 설정
- **로컬 레포지토리**: ISO 및 YUM 레포지토리 지원 (RHEL/CentOS)
- **고가용성**: Multi-master 구성 지원 (kube-vip)
- **크로스 플랫폼**: Ubuntu 및 RHEL/CentOS 지원

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
- **Ubuntu**: 20.04 LTS, 22.04 LTS
- **RHEL/CentOS**: 8.x, 9.x
- **Rocky Linux**: 8.x, 9.x

### Kubernetes 버전
- **기본**: 1.27.14 (기본값)
- **지원**: 1.25.x - 1.28.x

## 🚀 빠른 시작

### 사전 요구사항

1. **제어 노드 설정** (Ansible 실행 노드):
   ```bash
   # Ansible 설치 (Ubuntu/Debian)
   sudo apt update
   sudo apt install ansible python3-pip

   # Ansible 설치 (RHEL/CentOS)
   sudo yum install epel-release
   sudo yum install ansible python3-pip
   ```

2. **대상 노드 준비**:
   - 깨끗한 OS 설치 (Ubuntu 20.04+ 또는 RHEL 8+)
   - Root 접근 또는 sudo 사용자
   - 모든 노드 간 네트워크 연결
   - SSH 키 기반 인증

### SSH 키 설정

1. **SSH 키 쌍 생성** (제어 노드에서):
   ```bash
   ssh-keygen -t rsa -b 4096 -C "ansible@kubernetes"
   ```

2. **공개 키를 모든 대상 노드에 복사**:
   ```bash
   ssh-copy-id root@<master-node-ip>
   ssh-copy-id root@<worker-node-ip>
   ```

3. **연결 테스트**:
   ```bash
   ssh root@<node-ip> "uptime"
   ```

### 프로젝트 구조

```
kubernetes-kubeadm/
├── group_vars/
│   └── all.yml                       # 전역 변수
├── inventory.ini                     # 인벤토리 파일
├── roles/                            # Ansible 역할
│   ├── common/                       # 기본 시스템 설정
│   ├── configure_sysctl/             # 커널 파라미터
│   ├── configure_chrony/             # NTP 시간 동기화
│   ├── configure_repo/               # 레포지토리 설정
│   ├── install_os_package/           # OS 패키지
│   ├── install_containerd/           # 컨테이너 런타임
│   ├── setup-docker-credentials/     # 레지스트리 인증
│   ├── install_kubernetes/           # K8s 설치
│   ├── install_flannel/              # CNI 플러그인
│   ├── extend_k8s_certs/             # 인증서 연장
│   ├── configure_coredns_hosts/      # CoreDNS 설정
│   ├── nfs-server/                   # NFS 서버
│   ├── setup-local-repo/             # 로컬 레포지토리
│   └── harbor-project-setup/         # Harbor 설정
├── site.yml                          # 메인 플레이북
├── reset_cluster.yml                 # 클러스터 초기화
├── k8s-setup.sh                      # 독립 실행 스크립트
└── README.md                         # 이 파일
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

[pre-installs]
master1 ansible_host=192.168.135.31

[all:vars]
ansible_user=root
ansible_become=true
ansible_become_method=sudo
```

### 2. 전역 변수 설정

`group_vars/all.yml`을 환경에 맞게 편집:

```yaml
# Kubernetes 기본 설정
kubernetes_version: '1.27.14'
dns_domain: cluster.local
service_subnet: 10.96.0.0/12
pod_subnet: 10.244.0.0/16

# 고가용성 설정 (다중 마스터)
master_ha: false                      # true로 설정 시 HA 구성
kube_vip_port: 6443
kube_vip_interface: ens18
kube_vip_address: 192.168.135.30     # HA 구성 시 VIP 주소

# 컨테이너 런타임
containerd_version: "1.7.6"

# 시스템 설정
set_timezone: Asia/Seoul

# NTP/시간 동기화
use_local_ntp: true                   # true: master1을 NTP 서버로, false: 외부 NTP
external_ntp_servers:
  - "pool.ntp.org"
  - "time.google.com"
cluster_network: "192.168.0.0/16"    # 로컬 NTP 접근 허용 네트워크

# 네트워크 플러그인
network_plugin: "flannel"

# 마스터 노드 스케줄링 (단일 노드 클러스터용)
allow_master_scheduling: true         # 단일 노드 시 true

# 인증서 연장 (10년)
extend_k8s_certificates: true

# 병렬 실행 제어
parallel_execution:
  system_preparation: 0               # 0 = 모든 호스트 병렬
  package_installation: 0
  kubernetes_installation: 0

# 로컬 레포지토리 설정 (RHEL/CentOS)
setup_local_repo: true
use_yum_repo_directory: true
yum_repo_directory: "/root/yum-repo"
yum_repo_web_port: 8080

use_iso_repo: true
iso_file_path: "/root/rhel-9.4-x86_64-dvd.iso"
iso_mount_point: "/mnt/cdrom"
iso_device: "/dev/sr0"
use_iso_device: true

local_repo_web_server: "httpd"       # httpd 또는 nginx
local_repo_server_ip: "{{ ansible_default_ipv4.address }}"

# 컨테이너 레지스트리 설정
insecure_registries:
  - "cr.makina.rocks"
  - "harbor.runway.test"

# Docker 레지스트리 인증
docker_login_required: true
docker_registries:
  - registry: "cr.makina.rocks"
    protocol: "https"
    username: "mrx.dev"
    password: "your-password"
  - registry: "harbor.runway.test"
    protocol: "http"
    username: "admin"
    password: "Harbor12345"

# 레지스트리 호스트 매핑
registry_hosts:
  "harbor.runway.test": "192.168.135.28"

# CoreDNS 호스트 설정
configure_coredns_hosts: true

# NFS 서버 설정
nfs_server_enabled: true
nfs_exports:
  - path: "/nfs"
    options: "rw,sync,no_root_squash"
    clients: "*"

# GPU 드라이버 설치
install_gpu_driver: false
driver_version: "570.124.06"
```

## 🚀 설치

### 전체 클러스터 설치

```bash
# 1. 저장소 클론
git clone <repository-url>
cd kubernetes-kubeadm

# 2. 설정 파일 편집
vim inventory.ini
vim group_vars/all.yml

# 3. 연결 테스트
ansible all -i inventory.ini -m ping

# 4. 전체 클러스터 설치
ansible-playbook -i inventory.ini site.yml
```

### 단계별 설치

```bash
# Phase 0: 로컬 레포지토리 설정 (RHEL/CentOS, 선택사항)
ansible-playbook -i inventory.ini site.yml --tags local-repo

# Phase 1: 시스템 준비
ansible-playbook -i inventory.ini site.yml --tags base,system,packages

# Phase 2: Kubernetes 설치
ansible-playbook -i inventory.ini site.yml --tags kubernetes

# Phase 3: 네트워크 플러그인
ansible-playbook -i inventory.ini site.yml --tags networking

# Phase 4-8: 추가 기능
ansible-playbook -i inventory.ini site.yml --tags k8s-certs,coredns-hosts,nfs
```

### 특정 호스트만 설치

```bash
# master1만 설치
ansible-playbook -i inventory.ini site.yml --limit master1

# worker 노드만 설치
ansible-playbook -i inventory.ini site.yml --limit workers
```

## 🏷️ Ansible Tags

### 주요 Phase Tags

| Phase | Tag | 설명 | 적용 대상 |
|-------|-----|------|-----------|
| **Phase 0** | `local-repo` | 로컬 레포지토리 설정 | master1 (RHEL/CentOS) |
| **Phase 1** | `base`, `system` | 시스템 기본 설정 | 모든 노드 |
| **Phase 1** | `time` | 시간 동기화 (Chrony) | 모든 노드 |
| **Phase 1** | `packages` | OS 패키지 설치 | 모든 노드 |
| **Phase 1** | `container` | 컨테이너 런타임 (containerd) | 모든 노드 |
| **Phase 1** | `docker-credentials` | 레지스트리 인증 | 모든 노드 |
| **Phase 2** | `kubernetes`, `cluster` | Kubernetes 설치 | 모든 노드 |
| **Phase 3** | `networking` | CNI 플러그인 (Flannel) | Master 노드 |
| **Phase 4** | `scheduling` | Master 스케줄링 허용 | Master 노드 |
| **Phase 5** | `certificates`, `k8s-certs` | 인증서 10년 연장 | Master 노드 |
| **Phase 6** | `coredns-hosts` | CoreDNS 호스트 설정 | Master 노드 |
| **Phase 7** | `nfs` | NFS 서버 설정 | master1 |
| **Phase 8** | `harbor-setup` | Harbor 프로젝트 설정 | 모든 노드 |

### 로컬 레포지토리 세부 Tags (Phase 0)

| Tag | 설명 | 작업 내용 |
|-----|------|-----------|
| `local-repo` | 전체 로컬 레포 설정 | 모든 작업 포함 |
| `pre-setup` | 사전 설정 | ISO 마운트, 임시 레포 구성 |
| `web-server` | 웹 서버 설치 | httpd/nginx 설치 및 구성 |
| `firewall` | 방화벽 설정 | HTTP 포트 허용 |
| `yum-repo-dir` | YUM 레포 디렉토리 | /root/yum-repo 설정 |
| `iso-repo` | ISO 레포지토리 | ISO 마운트 및 서비스 |
| `web-config` | 웹 서버 설정 | httpd/nginx 상세 설정 |
| `repo-config` | 레포 설정 파일 | .repo 파일 생성 |
| `fstab` | fstab 설정 | ISO 영구 마운트 |
| `selinux` | SELinux 설정 | httpd context 설정 |

### 시스템 준비 세부 Tags (Phase 1)

| Tag | 설명 | 작업 내용 |
|-----|------|-----------|
| `base` | 기본 시스템 설정 | 호스트명, 방화벽, SELinux |
| `system` | 시스템 구성 | Swap, 커널 모듈, sysctl |
| `time` | 시간 동기화 | Chrony/NTP 설정 |
| `packages` | 패키지 설치 | 필수 OS 패키지 |
| `container` | 컨테이너 런타임 | containerd 설치 및 구성 |
| `docker-credentials` | 레지스트리 인증 | nerdctl login 설정 |

### 사용 예시

```bash
# 1. 로컬 레포지토리만 설정
ansible-playbook -i inventory.ini site.yml --tags local-repo

# 2. 로컬 레포 pre-setup만 (ISO 마운트)
ansible-playbook -i inventory.ini site.yml --tags pre-setup

# 3. 시스템 준비만 (Kubernetes 제외)
ansible-playbook -i inventory.ini site.yml --tags base,system,time,packages,container

# 4. Kubernetes만 설치 (시스템 준비 완료 가정)
ansible-playbook -i inventory.ini site.yml --tags kubernetes,networking

# 5. 인증서만 10년으로 연장
ansible-playbook -i inventory.ini site.yml --tags k8s-certs

# 6. CoreDNS 호스트 업데이트만
ansible-playbook -i inventory.ini site.yml --tags coredns-hosts

# 7. 여러 tag 조합
ansible-playbook -i inventory.ini site.yml --tags "packages,container,kubernetes"

# 8. 특정 호스트 + 특정 tag
ansible-playbook -i inventory.ini site.yml --tags local-repo --limit master1

# 9. 로컬 레포 웹서버 재설정
ansible-playbook -i inventory.ini site.yml --tags web-config

# 10. NFS 서버만 설정
ansible-playbook -i inventory.ini site.yml --tags nfs
```

### Tag 조합 권장 패턴

```bash
# 빠른 재설치 (시스템 준비 완료 후)
ansible-playbook -i inventory.ini site.yml --tags "kubernetes,networking"

# 레포지토리 + 패키지만
ansible-playbook -i inventory.ini site.yml --tags "local-repo,packages"

# 컨테이너 런타임 + Kubernetes
ansible-playbook -i inventory.ini site.yml --tags "container,kubernetes"

# 전체 재설치 (로컬 레포 제외)
ansible-playbook -i inventory.ini site.yml --skip-tags local-repo

# 테스트 환경 빠른 설치 (최소 구성)
ansible-playbook -i inventory.ini site.yml --tags "base,container,kubernetes,networking"
```

## 🔧 설치 후 작업

### 1. 클러스터 상태 확인

```bash
# SSH로 master 노드 접속
ssh root@<master-node-ip>

# 노드 상태 확인
kubectl get nodes -o wide

# 시스템 Pod 확인
kubectl get pods -A

# 클러스터 정보
kubectl cluster-info
```

### 2. kubectl 설정 (일반 사용자)

```bash
# kubeconfig 복사
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# kubectl alias 사용 (자동 설정됨)
k get nodes          # kubectl get nodes
kgp                  # kubectl get pods
kgn                  # kubectl get nodes
kga                  # kubectl get all
kgpa                 # kubectl get pods -A
```

### 3. 샘플 애플리케이션 배포

```bash
# nginx 배포
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=NodePort

# 배포 확인
kubectl get pods
kubectl get services

# 서비스 접근
NODE_PORT=$(kubectl get svc nginx -o jsonpath='{.spec.ports[0].nodePort}')
curl http://<node-ip>:$NODE_PORT
```

### 4. 기본 클러스터 작업

```bash
# Deployment 확장
kubectl scale deployment nginx --replicas=3

# 리소스 사용량 확인
kubectl top nodes
kubectl top pods

# Pod 로그 확인
kubectl logs deployment/nginx

# Pod 내부 접속
kubectl exec -it <pod-name> -- /bin/bash
```

## 🔍 문제 해결

### 일반적인 문제

#### 1. 노드 NotReady 상태

```bash
# kubelet 로그 확인
sudo journalctl -u kubelet -f

# CNI (Flannel) 확인
kubectl get pods -n kube-system | grep flannel

# Flannel 로그 확인
kubectl logs -n kube-system -l app=flannel
```

#### 2. Pod Pending 상태

```bash
# Pod 상세 정보
kubectl describe pod <pod-name>

# 노드 리소스 확인
kubectl describe nodes

# 이벤트 확인
kubectl get events --sort-by='.lastTimestamp'
```

#### 3. Worker 노드 Join 실패

```bash
# Master에서 join 명령어 재생성
kubeadm token create --print-join-command

# 노드가 이미 join되었는지 확인
kubectl get nodes

# Worker 노드 초기화 후 재시도
kubeadm reset
# 그 다음 join 명령어 실행
```

#### 4. 네트워크 문제

```bash
# Flannel 상태 확인
kubectl get pods -n kube-system -l app=flannel

# Pod 간 통신 테스트
kubectl run test-pod --image=busybox --rm -it -- /bin/sh
# Pod 내에서: ping <다른-pod-ip>

# DNS 테스트
kubectl run test-dns --image=busybox --rm -it -- nslookup kubernetes.default
```

#### 5. 로컬 레포지토리 문제

```bash
# httpd 상태 확인
systemctl status httpd

# 레포지토리 파일 확인
cat /etc/yum.repos.d/*.repo

# 레포지토리 테스트
yum repolist

# ISO 마운트 확인
mountpoint /mnt/cdrom
ls -la /mnt/cdrom

# 웹서버 접근 테스트
curl http://localhost:8080/iso-repo/
curl http://localhost:8080/yum-repo/
```

### 상태 확인 스크립트

```bash
#!/bin/bash
echo "=== Kubernetes 클러스터 상태 확인 ==="

echo -e "\n클러스터 정보:"
kubectl cluster-info

echo -e "\n노드 목록:"
kubectl get nodes -o wide

echo -e "\n시스템 Pod:"
kubectl get pods -n kube-system

echo -e "\nFlannel 네트워크:"
kubectl get pods -n kube-system -l app=flannel

echo -e "\n리소스 사용량:"
kubectl top nodes 2>/dev/null || echo "Metrics server not installed"

echo -e "\n최근 이벤트:"
kubectl get events --sort-by='.lastTimestamp' | tail -10
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
| 8080 | TCP | 전체 | 로컬 레포지토리 (선택) |

## 🎯 추가 기능

### 클러스터 초기화

```bash
# 전체 클러스터 리셋
ansible-playbook -i inventory.ini reset_cluster.yml

# 특정 노드만 리셋
ansible-playbook -i inventory.ini reset_cluster.yml --limit worker1
```

### 독립 실행 스크립트 (Ansible 없이)

```bash
# Ansible 없이 단일 노드에 설치
chmod +x k8s-setup.sh
./k8s-setup.sh

# 자세한 사용법은 k8s-setup-README.md 참조
```

### 인증서 10년 연장

```bash
# 모든 Master 노드의 인증서 연장
ansible-playbook -i inventory.ini site.yml --tags k8s-certs

# 또는 수동으로 (master 노드에서)
./k8s_10y.sh all
```

### GPU 지원

```yaml
# group_vars/all.yml에서 활성화
install_gpu_driver: true
driver_version: "570.124.06"
nvidia_runtime: true
```

```bash
# GPU 노드 확인
kubectl get nodes -o json | jq '.items[].status.capacity'
```

### High Availability (HA) 구성

```yaml
# group_vars/all.yml
master_ha: true
kube_vip_address: 192.168.135.30
```

```ini
# inventory.ini
[masters]
master1 ansible_host=192.168.135.31
master2 ansible_host=192.168.135.32
master3 ansible_host=192.168.135.33
```

### NFS Provisioner

```bash
# NFS 서버 확인 (master1)
showmount -e master1

# NFS provisioner 배포 (별도 설치 필요)
# https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner
```

## 📚 추가 리소스

- [Kubernetes 공식 문서](https://kubernetes.io/ko/docs/)
- [kubectl 치트시트](https://kubernetes.io/ko/docs/reference/kubectl/cheatsheet/)
- [Ansible 문서](https://docs.ansible.com/)
- [Flannel 문서](https://github.com/flannel-io/flannel)
- [containerd 문서](https://containerd.io/)

## 🤝 기여

이슈 및 풀 리퀘스트를 환영합니다!

## 📝 라이선스

MIT License

## ✨ 주요 특징

- ✅ **완전 자동화**: 한 번의 명령으로 전체 클러스터 배포
- ✅ **크로스 플랫폼**: Ubuntu/RHEL/CentOS 지원
- ✅ **오프라인 설치**: 로컬 레포지토리 지원 (ISO/YUM)
- ✅ **고가용성**: Multi-master 구성 지원 (kube-vip)
- ✅ **병렬 실행**: 빠른 설치를 위한 병렬 작업
- ✅ **유연한 Tag**: 원하는 구성 요소만 선택 설치
- ✅ **인증서 관리**: 10년 인증서 자동 연장
- ✅ **GPU 지원**: NVIDIA GPU 드라이버 자동 설치
- ✅ **레지스트리 통합**: Private registry 인증 지원
- ✅ **모듈화**: 재사용 가능한 Ansible 역할

---

**Made with ❤️ for Kubernetes Administrators**
