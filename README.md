# kubernetes-kubeadm

## Optimized Kubernetes Cluster Deployment with Ansible

This project provides an optimized, centralized approach to deploying Kubernetes clusters on **Ubuntu** and **CentOS** systems using kubeadm.

### ✨ Key Features

- **Multi-OS Support**: Seamless deployment on Ubuntu/Debian and CentOS/RHEL systems
- **Centralized Package Management**: All OS-specific packages managed in `group_vars/all.yml`
- **Flexible Configuration**: Easy customization of packages and components per environment
- **OS Compatibility Validation**: Automatic system validation before deployment
- **Optimized Performance**: Removed duplications and improved error handling

### 🚀 Quick Start

#### 1. Basic Deployment
```bash
ansible-playbook -i inventory.ini site.yml
```

#### 2. Deploy with specific tags
```bash
# Only validation and system setup
ansible-playbook -i inventory.ini site.yml --tags "validation,system_setup"

# Skip validation
ansible-playbook -i inventory.ini site.yml --skip-tags "validation"
```

### 📦 Package Management

All OS-specific packages are centrally managed in `group_vars/all.yml`. You can easily customize packages for your environment:

#### Adding Packages
```yaml
# In group_vars/all.yml
system_packages:
  ubuntu:
    - bash-completion
    - jq
    - your-new-package    # Add here
  centos:
    - bash-completion
    - jq  
    - your-new-package    # Add here
```

#### Controlling Optional Components
```yaml
# In group_vars/all.yml
install_dev_tools: true          # Enable development tools
install_network_storage: false   # Disable NFS packages
install_time_sync: true          # Enable chrony
```

### 🛠 Supported Operating Systems

- **Ubuntu**: 18.04, 20.04, 22.04
- **Debian**: 10, 11
- **CentOS**: 7, 8, Stream
- **RHEL**: 7, 8, 9
- **Rocky Linux**: 8, 9
- **AlmaLinux**: 8, 9

### 📋 Deployment Stages

1. **Validation** - OS compatibility and system requirements check
2. **System Setup** - Base system configuration and packages
3. **Kubernetes Setup** - Cluster initialization and worker joining
4. **Applications** - Additional services and applications

### 🔧 Configuration Files

- `group_vars/all.yml` - Central configuration for all variables and packages
- `inventory.ini` - Host definitions and groupings
- `site.yml` - Main playbook with optimized role execution

### 📝 Examples

#### Custom Package Configuration
```yaml
# Add monitoring tools
system_packages:
  ubuntu:
    - htop
    - iotop
    - netstat-nat
  centos:
    - htop
    - iotop
    - net-tools

# Enable development environment
install_dev_tools: true
dev_tools_packages:
  ubuntu:
    - git
    - build-essential
    - python3-pip
    - nodejs
  centos:
    - git
    - gcc
    - gcc-c++
    - python3-pip
    - nodejs
```

### 🎯 Advanced Usage

#### Environment-specific Deployments
```bash
# Production deployment (minimal packages)
ansible-playbook -i inventory.ini site.yml -e "install_dev_tools=false"

# Development deployment (all packages)
ansible-playbook -i inventory.ini site.yml -e "install_dev_tools=true"
```

#### Selective Role Execution
```bash
# Only system preparation
ansible-playbook -i inventory.ini site.yml --tags "system_setup"

# Only Kubernetes applications
ansible-playbook -i inventory.ini site.yml --tags "applications"
```

## 🔄 고가용성(HA) 및 마스터 노드 관리

### HA 모드 설정

#### 단일 마스터 모드 (기본값)
```yaml
# group_vars/all.yml
ha_mode: false
```
- 빠른 설치 및 테스트 환경에 적합
- 단일 장애점(SPOF) 존재
- 리소스 사용량 최소화

#### 다중 마스터 HA 모드
```yaml
# group_vars/all.yml
ha_mode: true
kubevip_interface: "eth0"          # 네트워크 인터페이스 설정
kubevip_address: "192.168.0.30"    # VIP 주소 (wildcard_ip 사용)
```
- kube-vip를 통한 자동 페일오버
- API 서버 고가용성 보장
- 운영 환경 권장

### 📋 마스터 노드 추가 방법

#### 1. Inventory 파일 수정
```ini
# inventory.ini
[masters]
master1 ansible_host=192.168.0.21
master2 ansible_host=192.168.0.25    # 새로 추가
master3 ansible_host=192.168.0.26    # 새로 추가

[installs]
master1 ansible_host=192.168.0.21
```

#### 2. HA 모드 활성화
```yaml
# group_vars/all.yml
ha_mode: true
token_auto_regenerate: true
```

#### 3. 마스터 토큰 재생성 및 노드 추가
```bash
# 토큰 재생성 및 새 마스터 노드 조인
ansible-playbook -i inventory.ini site.yml --tags "master_tokens"

# 또는 전체 재실행 (권장)
ansible-playbook -i inventory.ini site.yml
```

### 🛠 실행 시나리오별 명령어

#### 시나리오 1: 새로운 단일 마스터 클러스터 설치
```bash
# group_vars/all.yml에서 ha_mode: false 설정
ansible-playbook -i inventory.ini site.yml
```

#### 시나리오 2: 새로운 HA 클러스터 설치
```bash
# group_vars/all.yml에서 ha_mode: true 설정
ansible-playbook -i inventory.ini site.yml
```

#### 시나리오 3: 단일 마스터를 HA로 전환
```bash
# 1. group_vars/all.yml에서 ha_mode: false → true 변경
# 2. inventory.ini에 추가 마스터 노드 등록
# 3. 재실행
ansible-playbook -i inventory.ini site.yml
```

#### 시나리오 4: 기존 HA 클러스터에 마스터 추가
```bash
# 1. inventory.ini에 새 마스터 노드 추가
# 2. 토큰 재생성 태그만 실행
ansible-playbook -i inventory.ini site.yml --tags "master_tokens"
```

### 📊 클러스터 상태 확인

#### 기본 상태 확인
```bash
# 클러스터 상태 검증 실행
ansible-playbook -i inventory.ini site.yml --tags "post_status"
```

#### 수동 상태 확인 명령어
```bash
# 노드 상태 확인
kubectl get nodes -o wide

# kube-vip 상태 확인 (HA 모드)
kubectl get pods -n kube-system | grep kube-vip

# API 서버 연결성 테스트
curl -k https://192.168.0.30:6443/healthz  # VIP 주소 사용

# 클러스터 정보
kubectl cluster-info
```

### ⚠️ 주의사항

1. **네트워크 인터페이스**: `kubevip_interface`를 환경에 맞게 설정 (eth0, ens33, enp0s3 등)
2. **방화벽**: 6443 포트(API 서버), 2379-2380 포트(etcd) 개방 필요
3. **VIP 주소**: 기존 네트워크와 충돌하지 않는 사용 가능한 IP 주소 선택
4. **토큰 보안**: 마스터 조인 후 불필요한 토큰 및 certificate-key 삭제 권장

### 🔧 문제 해결

#### kube-vip 문제
```bash
# kube-vip 로그 확인
kubectl logs -n kube-system -l component=kube-vip

# VIP 연결 테스트
ping 192.168.0.30
telnet 192.168.0.30 6443
```

#### 마스터 조인 실패
```bash
# 토큰 재생성
kubeadm token create --print-join-command

# certificate-key 재생성 (HA 모드)
kubeadm init phase upload-certs --upload-certs
```