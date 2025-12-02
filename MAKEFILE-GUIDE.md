# Makefile 사용 가이드

이 문서는 Kubernetes 클러스터 설치를 위한 Makefile 사용법을 설명합니다.

## 📋 목차

- [기본 사용법](#기본-사용법)
- [설치 시나리오](#설치-시나리오)
- [명령어 카테고리](#명령어-카테고리)
- [실전 예제](#실전-예제)

## 기본 사용법

### Help 확인

```bash
make help
# 또는
make
```

모든 사용 가능한 명령어와 설명이 표시됩니다.

## 설치 시나리오

### 1. 신규 클러스터 설치 (권장)

```bash
# 1단계: 연결 테스트
make ping

# 2단계: 전체 설치
make install

# 3단계: 상태 확인
make check-cluster
```

### 2. 단계별 설치

```bash
# Phase 1: 시스템 준비
make install-step1

# Phase 2: Kubernetes 설치
make install-step2

# Phase 3: 네트워크 플러그인
make install-step3
```

### 3. 최소 구성 설치 (개발/테스트)

```bash
make install-minimal
```

최소 구성: sysctl + containerd + kubernetes + networking

### 4. 프로덕션 설치 (전체 기능)

```bash
make install-production
```

전체 기능: 레지스트리 인증, 인증서 연장, CoreDNS, Harbor 포함

### 5. 부분 설치 (특정 기능만)

```bash
# Sysctl만 설정
make tag-sysctl

# 컨테이너 런타임만
make tag-container

# Kubernetes만 재설치
make tag-kubernetes

# 네트워크 플러그인만
make tag-networking
```

## 명령어 카테고리

### 일반 명령어

| 명령어 | 설명 | 사용 예시 |
|--------|------|-----------|
| `make help` | 명령어 목록 표시 | 처음 시작할 때 |
| `make ping` | 호스트 연결 테스트 | 설치 전 확인 |
| `make check-cluster` | 클러스터 상태 확인 | 설치 후 검증 |

### 설치 명령어

| 명령어 | 설명 | 소요 시간 |
|--------|------|-----------|
| `make install` | 전체 클러스터 설치 | 10-20분 |
| `make install-step1` | 시스템 준비 | 3-5분 |
| `make install-step2` | Kubernetes 설치 | 5-10분 |
| `make install-step3` | 네트워크 플러그인 | 1-2분 |
| `make install-minimal` | 최소 구성 | 8-15분 |
| `make install-production` | 프로덕션 전체 | 15-25분 |

### Tag 기반 명령어

| 명령어 | 대상 | 설명 |
|--------|------|------|
| `make tag-sysctl` | 모든 노드 | Sysctl 파라미터 설정 |
| `make tag-packages` | 모든 노드 | OS 패키지 설치 |
| `make tag-container` | 모든 노드 | Containerd 설치 |
| `make tag-docker-credentials` | 모든 노드 | 레지스트리 인증 |
| `make tag-kubernetes` | 모든 노드 | K8s 설치 |
| `make tag-networking` | Master | CNI 플러그인 |
| `make tag-certs` | Master | 인증서 연장 |
| `make tag-coredns` | Master | CoreDNS 설정 |
| `make tag-harbor` | 모든 노드 | Harbor 설정 |
| `make tag-scheduling` | Master | Master 스케줄링 |
| `make tag-local-registry` | Installs | 로컬 레지스트리 |

### 호스트별 명령어

| 명령어 | 대상 | 사용 시나리오 |
|--------|------|---------------|
| `make limit-master` | Masters | Master만 업데이트 |
| `make limit-workers` | Workers | Worker만 업데이트 |
| `make limit-master1` | master1 | 특정 노드만 |

### 리셋 명령어

| 명령어 | 대상 | 위험도 | 확인 절차 |
|--------|------|--------|-----------|
| `make reset` | 전체 | ⚠️ 높음 | Y/N 확인 |
| `make reset-workers` | Workers | ⚠️ 중간 | Y/N 확인 |

### 유틸리티 명령어

| 명령어 | 출력 | 용도 |
|--------|------|------|
| `make show-inventory` | 호스트 목록 | 인벤토리 확인 |
| `make show-variables` | 변수 설정 | 설정값 확인 |
| `make lint` | 문법 검사 결과 | 문법 오류 검사 |
| `make list-tags` | 사용 가능한 tags | Tag 확인 |
| `make list-tasks` | 모든 tasks | Task 확인 |

### 고급 명령어

| 명령어 | 설명 | 주의사항 |
|--------|------|----------|
| `make install-ha` | HA 클러스터 | master_ha: true 필요 |
| `make reinstall-k8s` | K8s 재설치 | 시스템 준비 완료 가정 |
| `make update-registry` | 레지스트리 업데이트 | 인증 + CoreDNS |
| `make dry-run` | 시뮬레이션 | 실제 변경 없음 |

### 개발 명령어

| 명령어 | 출력 | 용도 |
|--------|------|------|
| `make test-connection` | 그룹별 연결 상태 | 상세 연결 테스트 |
| `make get-join-command` | Join 명령어 | Worker 추가 시 |
| `make check-versions` | 설치된 버전 | 버전 확인 |

### 커스텀 명령어 실행

| 명령어 | 대상 | 설명 |
|--------|------|------|
| `make cmd-all CMD="..."` | 모든 호스트 | 모든 노드에서 명령 실행 |
| `make cmd-masters CMD="..."` | Master 노드 | Master에서만 명령 실행 |
| `make cmd-workers CMD="..."` | Worker 노드 | Worker에서만 명령 실행 |
| `make cmd-installs CMD="..."` | Installs 노드 | Installs에서만 명령 실행 |
| `make command CMD="..."` | 모든 호스트 | cmd-all의 별칭 |

## 실전 예제

### 예제 1: 신규 클러스터 전체 설치

```bash
# 1. inventory.ini와 group_vars/all.yml 설정 완료

# 2. 연결 테스트
make ping

# 3. 인벤토리 확인
make show-inventory

# 4. 변수 확인
make show-variables

# 5. 전체 설치 (Dry run)
make dry-run

# 6. 실제 설치
make install

# 7. 상태 확인
make check-cluster
```

### 예제 2: 단일 노드 테스트 클러스터

```bash
# inventory.ini에 master1만 설정
# group_vars/all.yml: allow_master_scheduling: true

make ping
make limit-master1
make check-cluster
```

### 예제 3: 기존 클러스터에 Worker 추가

```bash
# 1. Join 명령어 가져오기
make get-join-command

# 2. inventory.ini에 새 worker 추가

# 3. 새 worker만 설치
make limit-workers

# 4. 확인
make check-cluster
```

### 예제 4: 레지스트리 인증 업데이트

```bash
# group_vars/all.yml에서 레지스트리 정보 수정

make update-registry
```

### 예제 5: 인증서 연장

```bash
# 10년 인증서로 연장
make tag-certs

# 확인 (master 노드에서)
ssh master1 "kubeadm certs check-expiration"
```

### 예제 6: CoreDNS 호스트 추가

```bash
# group_vars/all.yml에서 registry_hosts 수정

make tag-coredns

# 확인
ssh master1 "kubectl get cm coredns -n kube-system -o yaml"
```

### 예제 7: 문제 해결 - Kubernetes만 재설치

```bash
# 1. 클러스터 초기화
make reset

# 2. Kubernetes만 재설치 (시스템 준비는 유지)
make reinstall-k8s

# 3. 상태 확인
make check-cluster
```

### 예제 8: HA 클러스터 설치

```bash
# group_vars/all.yml:
#   master_ha: true
#   kube_vip_address: 192.168.135.30

# inventory.ini:
#   [masters]
#   master1 ansible_host=192.168.135.31
#   master2 ansible_host=192.168.135.32
#   master3 ansible_host=192.168.135.33

make install-ha
make check-cluster
```

### 예제 9: 로컬 레지스트리 배포

```bash
# group_vars/all.yml:
#   enable_local_registry: true

make tag-local-registry

# 확인
ssh master1 "nerdctl ps | grep registry"
```

### 예제 10: GPU 노드 설정

```bash
# group_vars/all.yml:
#   nvidia_runtime: true

# 1. NVIDIA Driver는 미리 설치되어 있어야 함

# 2. GPU 노드만 설치
make limit-workers

# 3. GPU 확인
make check-versions
ssh worker1 "nvidia-smi"
```

### 예제 11: 커스텀 명령어 실행

```bash
# 모든 호스트에서 uptime 확인
make cmd-all CMD="uptime"

# Master 노드에서만 kubectl 명령 실행
make cmd-masters CMD="kubectl get nodes -o wide"

# Worker 노드에서만 메모리 확인
make cmd-workers CMD="free -h"

# 모든 호스트에서 디스크 사용량 확인
make command CMD="df -h /data"

# Master에서 Pod 목록 확인
make cmd-masters CMD="kubectl get pods -A"

# Worker에서 containerd 상태 확인
make cmd-workers CMD="systemctl status containerd --no-pager"

# Installs 노드에서 로컬 레지스트리 확인
make cmd-installs CMD="nerdctl ps"
```

## 팁과 모범 사례

### 🔧 설치 전

1. **항상 연결 테스트**
   ```bash
   make ping
   ```

2. **설정 파일 확인**
   ```bash
   make show-variables
   make show-inventory
   ```

3. **Dry run으로 미리 확인**
   ```bash
   make dry-run
   ```

### 🚀 설치 중

1. **단계별 설치 권장** (처음 설치 시)
   ```bash
   make install-step1  # 시스템 준비
   make install-step2  # Kubernetes
   make install-step3  # 네트워크
   ```

2. **프로덕션은 전체 설치**
   ```bash
   make install-production
   ```

### ✅ 설치 후

1. **상태 확인**
   ```bash
   make check-cluster
   make check-versions
   ```

2. **버전 확인**
   ```bash
   make check-versions
   ```

### 🔍 문제 해결

1. **문법 검사**
   ```bash
   make lint
   ```

2. **연결 상태 확인**
   ```bash
   make test-connection
   ```

3. **Tags 확인**
   ```bash
   make list-tags
   ```

## 자주 하는 실수

### ❌ 잘못된 사용

```bash
# 연결 테스트 없이 바로 설치
make install  # ❌

# 설정 확인 없이 설치
make install  # ❌

# Dry run 없이 프로덕션 설치
make install-production  # ❌
```

### ✅ 올바른 사용

```bash
# 1. 연결 테스트
make ping

# 2. 설정 확인
make show-variables

# 3. Dry run
make dry-run

# 4. 실제 설치
make install
```

## 추가 리소스

- [README.md](./README.md) - 전체 프로젝트 문서
- [inventory.ini](./inventory.ini) - 인벤토리 설정
- [group_vars/all.yml](./group_vars/all.yml) - 전역 변수
- [Makefile](./Makefile) - 소스 코드

## 요약

| 작업 | 명령어 | 시간 |
|------|--------|------|
| 빠른 설치 | `make install` | 10-20분 |
| 최소 설치 | `make install-minimal` | 8-15분 |
| 프로덕션 설치 | `make install-production` | 15-25분 |
| 상태 확인 | `make check-cluster` | 즉시 |
| 클러스터 초기화 | `make reset` | 5분 |

---

**💡 Tip**: 처음 사용하시는 경우 `make help`로 시작하세요!
