# Kubernetes 독립 실행 설치 스크립트

Ansible 없이 단일 노드에서 Kubernetes를 설치할 수 있는 스크립트와 Makefile입니다.

## 📋 파일 구조

```
install_sh/
├── .env.example        # 환경 변수 예제 파일
├── .env                # 실제 환경 변수 (생성 필요, gitignore됨)
├── Makefile            # 단계별 설치를 위한 Makefile
├── k8s-setup.sh        # 전체 설치 스크립트
└── README.md           # 이 파일
```

## 🚀 빠른 시작

### 1단계: 환경 설정

```bash
# .env.example을 복사하여 .env 생성
cp .env.example .env

# 환경에 맞게 .env 편집
vim .env
```

### 2단계: 설치 방법 선택

#### 옵션 A: 전체 자동 설치 (Shell 스크립트)

```bash
chmod +x k8s-setup.sh
sudo ./k8s-setup.sh
```

#### 옵션 B: 단계별 설치 (Makefile - 권장)

```bash
# 도움말 확인
make help

# 전체 설치
sudo make all

# 또는 단계별 설치
sudo make repo          # 1. 저장소 설정
sudo make packages      # 2. 패키지 설치
sudo make system        # 3. 시스템 설정
sudo make sysctl        # 4. 커널 파라미터
sudo make containerd    # 5. 컨테이너 런타임
sudo make chrony        # 6. 시간 동기화
sudo make kubernetes    # 7. Kubernetes 설치
sudo make kubectl-setup # 8. kubectl 설정
sudo make summary       # 9. 설치 요약
```

## ⚙️ 환경 변수 설정 (.env)

### 필수 설정

```bash
# Kubernetes 버전
KUBERNETES_VERSION=1.27.14

# 네트워크 설정
POD_SUBNET=10.244.0.0/16
SERVICE_SUBNET=10.96.0.0/12

# 시스템 설정
TIMEZONE=Asia/Seoul
```

### RHEL/CentOS 저장소 설정

```bash
# 로컬 YUM 저장소 사용
USE_LOCAL_REPO=true
YUM_REPO_DIR=/root/yum-repo

# ISO 저장소 사용
USE_ISO_REPO=true
ISO_FILE_PATH=/root/rhel-9.4-x86_64-dvd.iso
ISO_MOUNT_POINT=/mnt/cdrom
```

### Ubuntu 저장소 설정

```bash
# 로컬 APT 저장소 사용
USE_LOCAL_APT_REPO=true
APT_REPO_URL=http://192.168.135.1:8080/ubuntu
APT_REPO_DISTRIBUTION=jammy

# 또는 미러 서버 사용
USE_LOCAL_APT_REPO=false
APT_REPO_MIRROR=http://kr.archive.ubuntu.com/ubuntu
APT_REPO_DISTRIBUTION=jammy
APT_COMPONENTS=main restricted universe multiverse
```

### 레지스트리 설정

```bash
# 비보안 레지스트리 (공백으로 구분)
INSECURE_REGISTRIES="cr.makina.rocks harbor.runway.test"
```

## 🎯 Makefile 타겟

### 기본 타겟

| 타겟 | 설명 |
|------|------|
| `make all` | 전체 설치 (모든 단계) |
| `make help` | 도움말 표시 |
| `make summary` | 설치 요약 표시 |
| `make clean` | 임시 파일 정리 |

### 단계별 타겟

| 타겟 | 설명 |
|------|------|
| `make check-root` | Root 권한 확인 |
| `make detect-os` | OS 감지 |
| `make repo` | 저장소 설정 |
| `make packages` | 필수 패키지 설치 |
| `make system` | 시스템 설정 (SELinux, 방화벽, swap 등) |
| `make sysctl` | 커널 파라미터 설정 |
| `make containerd` | Containerd 설치 |
| `make chrony` | 시간 동기화 설정 |
| `make kubernetes` | Kubernetes 패키지 설치 |
| `make kubectl-setup` | kubectl 자동완성 및 별칭 설정 |

### 조합 타겟

| 타겟 | 설명 |
|------|------|
| `make minimal` | 최소 설치 (repo + packages + kubernetes) |
| `make system-only` | 시스템 설정만 (system + sysctl) |
| `make runtime` | 컨테이너 런타임만 (containerd) |

## 📝 사용 예시

### 예시 1: 로컬 저장소 사용 (RHEL)

```bash
# .env 설정
cat > .env <<EOF
KUBERNETES_VERSION=1.27.14
USE_LOCAL_REPO=true
USE_ISO_REPO=true
ISO_FILE_PATH=/root/rhel-9.4-x86_64-dvd.iso
TIMEZONE=Asia/Seoul
EOF

# 설치 실행
sudo make all
```

### 예시 2: 미러 서버 사용 (Ubuntu)

```bash
# .env 설정
cat > .env <<EOF
KUBERNETES_VERSION=1.27.14
USE_LOCAL_APT_REPO=false
APT_REPO_MIRROR=http://kr.archive.ubuntu.com/ubuntu
APT_REPO_DISTRIBUTION=jammy
TIMEZONE=Asia/Seoul
EOF

# 설치 실행
sudo make all
```

### 예시 3: 단계별 설치 및 확인

```bash
# 저장소만 먼저 설정
sudo make repo

# 확인 후 패키지 설치
sudo make packages

# 시스템 설정
sudo make system
sudo make sysctl

# 런타임 설치
sudo make containerd

# Kubernetes 설치
sudo make kubernetes

# 설치 확인
make summary
```

### 예시 4: 특정 단계만 재실행

```bash
# containerd 설정을 변경한 후 재설치
sudo make containerd

# 저장소 설정 변경 후 재구성
sudo make repo
```

## 🔧 문제 해결

### 저장소 문제

```bash
# 저장소 정리 및 재설정
sudo make clean
sudo make repo

# RHEL: yum 캐시 정리
sudo yum clean all

# Ubuntu: apt 캐시 정리
sudo apt-get clean
```

### Containerd 문제

```bash
# Containerd 재설치
sudo systemctl stop containerd
sudo make containerd
sudo systemctl status containerd
```

### 로그 확인

```bash
# 시스템 로그
sudo journalctl -xeu containerd
sudo journalctl -xeu kubelet

# 커널 로그
dmesg | tail -50
```

## 📚 다음 단계

설치 완료 후:

1. **Master 노드 초기화**
   ```bash
   sudo kubeadm init \
     --pod-network-cidr=10.244.0.0/16 \
     --service-cidr=10.96.0.0/12
   ```

2. **kubectl 설정**
   ```bash
   mkdir -p $HOME/.kube
   sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
   sudo chown $(id -u):$(id -g) $HOME/.kube/config
   ```

3. **네트워크 플러그인 설치**
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
   ```

4. **클러스터 상태 확인**
   ```bash
   kubectl get nodes
   kubectl get pods -A
   ```

## 🔗 관련 문서

- [상위 README](../README.md) - Ansible 사용 방법
- [.env.example](./.env.example) - 모든 설정 옵션
- [Kubernetes 공식 문서](https://kubernetes.io/docs/)

## 💡 팁

1. **`.env` 파일 우선순위**: `.env` 파일의 설정이 기본값을 덮어씁니다
2. **재실행 안전**: 대부분의 타겟은 여러 번 실행해도 안전합니다
3. **OS 자동 감지**: 스크립트가 자동으로 RHEL/Ubuntu를 감지합니다
4. **로그 저장**: 출력을 파일로 저장하려면 `make all 2>&1 | tee install.log`
