# Kubernetes Setup Script (Bash 단독 설치)

Ansible 없이 순수 Bash 스크립트만으로 Kubernetes 클러스터 설치를 위한 사전 작업을 수행하는 스크립트입니다.

## 특징

- **Ansible 불필요**: 순수 bash 스크립트로 동작
- **OS 자동 감지**: RHEL/CentOS/Rocky와 Ubuntu 자동 감지
- **로컬 레포지토리 지원**: ISO 및 로컬 yum 레포지토리 설정
- **완전 자동화**: 한 번의 실행으로 모든 사전 작업 완료

## 스크립트가 수행하는 작업

### 1. 레포지토리 설정
- ISO 마운트 및 레포지토리 구성
- 로컬 yum 레포지토리 구성
- 기존 레포지토리 파일 정리

### 2. 필수 패키지 설치
- 기본 시스템 도구 (curl, wget, vim, net-tools 등)
- 컨테이너 런타임 의존성
- 네트워크 도구 (socat, conntrack, ipvsadm 등)

### 3. 시스템 설정
- SELinux 비활성화 (RHEL/CentOS)
- Firewall 비활성화
- Swap 비활성화
- 타임존 설정
- /etc/hosts 구성

### 4. 커널 파라미터 설정
- IP 포워딩 활성화
- Bridge 네트워크 설정
- Connection tracking 설정
- File descriptor 제한 증가

### 5. Containerd 설치 및 구성
- Containerd 설치
- systemd cgroup driver 활성화
- Insecure registry 설정

### 6. 시간 동기화 (Chrony)
- Chrony 설치 및 활성화
- NTP 서버 구성

### 7. Kubernetes 패키지 설치
- kubeadm 설치
- kubelet 설치
- kubectl 설치

### 8. kubectl 자동완성 설정
- Bash completion 설정
- kubectl 별칭(alias) 설정

## 사용 방법

### 1. 스크립트 실행 권한 부여
```bash
chmod +x k8s-setup.sh
```

### 2. 스크립트 편집 (선택사항)
스크립트 상단의 설정값을 환경에 맞게 수정하세요:

```bash
# Configuration (edit these values as needed)
KUBERNETES_VERSION="1.27.14"
CONTAINERD_VERSION="1.7.6"
POD_SUBNET="10.244.0.0/16"
SERVICE_SUBNET="10.96.0.0/12"
TIMEZONE="Asia/Seoul"

# Local repository settings
USE_LOCAL_REPO="true"
USE_ISO_REPO="true"
ISO_MOUNT_POINT="/mnt/cdrom"
ISO_FILE_PATH="/root/rhel-9.4-x86_64-dvd.iso"
YUM_REPO_DIR="/root/yum-repo"

# Registry settings
INSECURE_REGISTRIES=(
    "cr.makina.rocks"
    "harbor.runway.test"
)
```

### 3. 스크립트 실행
```bash
sudo ./k8s-setup.sh
```

## 스크립트 실행 후

스크립트 실행이 완료되면 다음 단계를 진행하세요:

### Master 노드 초기화
```bash
# 기본 초기화
kubeadm init --pod-network-cidr=10.244.0.0/16 --service-cidr=10.96.0.0/12

# 또는 HA 구성 시
kubeadm init \
  --control-plane-endpoint="192.168.135.30:6443" \
  --upload-certs \
  --pod-network-cidr=10.244.0.0/16 \
  --service-cidr=10.96.0.0/12
```

### kubectl 설정
```bash
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
```

### 네트워크 플러그인 설치 (Flannel)
```bash
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```

### Worker 노드 추가
Master 노드 초기화 후 출력되는 join 명령어를 Worker 노드에서 실행:
```bash
kubeadm join 192.168.135.30:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

### 클러스터 확인
```bash
# 노드 상태 확인
kubectl get nodes

# 모든 Pod 확인
kubectl get pods -A

# 클러스터 정보 확인
kubectl cluster-info
```

## 문제 해결

### ISO 마운트 실패
```bash
# ISO 파일 경로 확인
ls -la /root/rhel-9.4-x86_64-dvd.iso

# 수동으로 마운트
mkdir -p /mnt/cdrom
mount -o loop,ro /root/rhel-9.4-x86_64-dvd.iso /mnt/cdrom
```

### 패키지 설치 실패
```bash
# 레포지토리 확인
yum repolist

# 캐시 정리
yum clean all
yum makecache
```

### Containerd 시작 실패
```bash
# 설정 확인
cat /etc/containerd/config.toml

# 로그 확인
journalctl -u containerd -f

# 재시작
systemctl restart containerd
```

### Kubelet 시작 실패
```bash
# 로그 확인
journalctl -u kubelet -f

# kubeadm 초기화 전에는 정상적으로 시작되지 않을 수 있음
# 에러 메시지: "The HTTP call equal to 'curl -sSL http://localhost:10248/healthz' failed"
# → 정상입니다. kubeadm init 후 자동으로 시작됩니다.
```

## 다중 노드 설치

### Master 노드
```bash
# 1. Master 노드에서 스크립트 실행
./k8s-setup.sh

# 2. Kubernetes 초기화
kubeadm init --pod-network-cidr=10.244.0.0/16

# 3. kubectl 설정
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config

# 4. 네트워크 플러그인 설치
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```

### Worker 노드
```bash
# 1. Worker 노드에서 스크립트 실행
./k8s-setup.sh

# 2. Master에서 출력된 join 명령어 실행
kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

## 로컬 레포지토리 사용

### HTTP 서버를 통한 레포지토리 공유 (Master에서)
```bash
# 1. httpd 설치
yum install -y httpd

# 2. 레포지토리 디렉토리 설정
cat > /etc/httpd/conf.d/yum-repo.conf <<EOF
Alias /yum-repo /root/yum-repo
<Directory "/root/yum-repo">
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>

Alias /iso-repo /mnt/cdrom
<Directory "/mnt/cdrom">
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>
EOF

# 3. /root 디렉토리 권한 설정
chmod 755 /root

# 4. httpd 시작
systemctl enable httpd
systemctl start httpd
```

### Worker 노드에서 HTTP 레포지토리 사용
```bash
# ISO 레포지토리 설정
cat > /etc/yum.repos.d/master-iso.repo <<EOF
[master-iso-baseos]
name=Master ISO BaseOS Repository
baseurl=http://<master-ip>:8080/iso-repo/BaseOS
enabled=1
gpgcheck=0
priority=1

[master-iso-appstream]
name=Master ISO AppStream Repository
baseurl=http://<master-ip>:8080/iso-repo/AppStream
enabled=1
gpgcheck=0
priority=1
EOF

# YUM 레포지토리 설정
cat > /etc/yum.repos.d/master-yum.repo <<EOF
[master-yum-repo]
name=Master YUM Repository
baseurl=http://<master-ip>:8080/yum-repo
enabled=1
gpgcheck=0
priority=1
EOF

# 캐시 정리
yum clean all
yum repolist
```

## 스크립트 특징

### 에러 핸들링
- `set -e`: 에러 발생 시 스크립트 중단
- 각 단계별 로그 출력
- 색상 코딩된 메시지 (정보/경고/에러)

### OS 지원
- RHEL/CentOS/Rocky Linux (7/8/9)
- Ubuntu (18.04/20.04/22.04)

### 유연한 설정
- 스크립트 상단에서 모든 설정 변경 가능
- 환경에 맞게 커스터마이징 용이

## 참고 사항

- 이 스크립트는 Kubernetes 설치를 위한 **사전 작업만** 수행합니다
- 실제 클러스터 초기화는 `kubeadm init` 명령으로 수동으로 수행해야 합니다
- Production 환경에서는 보안 설정을 추가로 검토하세요
- SELinux와 Firewall을 비활성화하므로 보안 정책을 확인하세요

## 라이선스

이 스크립트는 kubernetes-kubeadm 프로젝트의 일부입니다.
