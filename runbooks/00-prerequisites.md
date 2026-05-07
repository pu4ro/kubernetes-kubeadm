# 00 — 사전 준비 / Prerequisites

> **언어 / Language:** [한국어](./00-prerequisites.md) · [English](./00-prerequisites.en.md)
> **위험도 / Risk:** Low · **소요 시간 / Duration:** 30–60분

## 목적 / Purpose

처음 클러스터를 설치하기 전 반드시 완료해야 하는 사전 작업: 제어 노드 준비, SSH 키, inventory, `group_vars/all.yml` 환경 맞춤. 이 문서를 마치면 [01 Day-0 설치](./01-day0-install.md) 시나리오로 바로 이동 가능.

## 사전 조건 / Preconditions (이 문서 자체의 사전 조건)

- [ ] 모든 노드에 OS 설치 완료 (Ubuntu 20.04+ 또는 RHEL/Rocky 8+)
- [ ] 노드 간 네트워크 연결성 (마스터끼리, 마스터-워커)
- [ ] 인터넷 연결 (오프라인 환경은 사내 미러 별도 준비 — [01 시나리오 B](./01-day0-install.md) 참조)
- [ ] SSH 접근 권한 (root 또는 NOPASSWD sudo)

## 1. 제어 노드 (Ansible 실행 호스트) 준비

Ansible 플레이북을 실행할 호스트를 정합니다 (보통 master1 또는 별도 관리 노드).

### Ubuntu/Debian
```bash
sudo apt update
sudo apt install -y ansible python3-pip sshpass git
```

### RHEL/CentOS
```bash
sudo yum install -y epel-release
sudo yum install -y ansible python3-pip sshpass git
```

### 버전 확인
```bash
ansible --version    # 2.10+ 권장
python3 --version    # 3.6+
```

## 2. SSH 키 설정

### 키 생성 (제어 노드에서)
```bash
# 새 키 생성
ssh-keygen -t rsa -b 4096 -C "ansible@kubernetes" -f ~/.ssh/id_rsa
# 비밀번호 없이 (Enter 두 번)
```

### 모든 대상 노드에 배포
```bash
# 마스터들
ssh-copy-id root@192.168.1.31
ssh-copy-id root@192.168.1.32
ssh-copy-id root@192.168.1.33

# 워커들
ssh-copy-id root@192.168.1.41
ssh-copy-id root@192.168.1.42
```

### 비밀번호 없이 접속 확인
```bash
ssh root@192.168.1.31 "uptime"
# 모든 노드에 대해 패스워드 없이 결과 출력되어야 함
```

> 비밀번호 인증을 일시적으로 사용하려면 `inventory.ini`에 `ansible_ssh_pass=...` 추가 또는 `--ask-pass` 옵션. 운영은 키 인증 권장.

## 3. 저장소 클론

```bash
git clone <repository-url>
cd kubernetes-kubeadm

# 디렉토리 구조 확인
ls -la
# Makefile, site.yml, inventory.ini, group_vars/, roles/, runbooks/, README.md ...
```

## 4. `inventory.ini` 작성

```ini
# inventory.ini

[masters]
master1 ansible_host=192.168.1.31
# master2 ansible_host=192.168.1.32   # HA 시 주석 해제
# master3 ansible_host=192.168.1.33

[workers]
worker1 ansible_host=192.168.1.41
worker2 ansible_host=192.168.1.42

# 'installs' 그룹: kubectl/admin.conf 배치할 노드 (보통 master1)
[installs]
master1 ansible_host=192.168.1.31

[all:vars]
ansible_user=root                                         # SSH 사용자
ansible_become=true                                       # sudo 사용
ansible_become_method=sudo
ansible_ssh_common_args='-o StrictHostKeyChecking=no'    # 첫 연결 시 fingerprint 자동 수락
```

### 그룹 의미

| 그룹 | 의미 | 비고 |
|---|---|---|
| `[masters]` | 컨트롤 플레인 노드 | HA 시 3개 (etcd 쿼럼) |
| `[workers]` | 워크로드 실행 노드 | 0개 가능 (단일 노드 클러스터) |
| `[installs]` | `kubectl` 도구 + `admin.conf` 배치 | 보통 master1 |

## 5. `group_vars/all.yml` 작성

⚠️ **중요**: 절대 `group_vars/all.yml`을 직접 만들지 마세요. 항상 `.example`을 복사:

```bash
# .example을 복사 (자격증명이 들어간 .yml 파일은 .gitignore 처리됨)
cp group_vars/all.yml.example group_vars/all.yml

# 환경에 맞게 편집
vim group_vars/all.yml
```

`group_vars/all.yml.example`에는 110개 변수 모두에 한국어 + 영어 상세 주석이 있습니다. 위에서부터 읽으며 자기 환경에 필요한 부분만 수정.

### 가장 자주 편집하는 변수

```yaml
# ── 환경 분기 ──
master_ha: false                       # 단일 마스터 vs HA
network_plugin: "flannel"              # CNI 선택
allow_master_scheduling: true          # 단일 노드면 true

# ── 인터넷 환경 ──
enable_official_k8s_repo: true         # 인터넷 가능
enable_official_containerd_repo: true

# ── 격리 환경 ──
# enable_official_k8s_repo: false      # 사내 미러 사용
# enable_ubuntu_repo: true
# ubuntu_repo_url: "http://mirror.example.com/ubuntu-repo"

# ── 사설 레지스트리 ──
docker_login_required: false           # 사설 레지스트리 미사용 시 false
# docker_login_required: true          # 사용 시 docker_registries 도 채움
```

전체 변수 가이드: [`group_vars/all.yml.example`](../group_vars/all.yml.example) 직접 열람.

## 6. 첫 연결 테스트

```bash
make ping
# 예상 출력:
# master1 | SUCCESS => { "ping": "pong" }
# worker1 | SUCCESS => { "ping": "pong" }
# worker2 | SUCCESS => { "ping": "pong" }
```

> 실패 시 [FAQ Q1](#faq) 참조.

## 7. 그룹별 연결 테스트
```bash
make test-connection
# masters, workers, installs 그룹 각각 ping
```

## 8. 인벤토리·변수 확인
```bash
make show-inventory          # inventory 트리 (호스트 + 그룹)
make show-variables-example  # 안전한 변수 파일 출력 (자격증명 미포함)
```

## 백업 권장사항

운영 환경에서 클러스터 사용 전 다음 백업 위치 확인:

| 백업 대상 | 위치 / 방법 | 용도 |
|---|---|---|
| **etcd 스냅샷** | `make` 명령 없음 — 직접 (06 runbook 참조) | 클러스터 메타데이터 복원 |
| **`/etc/kubernetes/pki/`** | tar로 압축 후 외부 저장소 | 인증서 손상 시 복구 |
| **`group_vars/all.yml`** | 외부 저장소 (gitignored) | 동일 설정으로 재배포 |
| **Persistent Volumes** | 외부 NFS / S3 / Ceph (외부 클러스터) | 워크로드 데이터 보존 |
| **Harbor/레지스트리 이미지** | Harbor 자체 백업 | 격리 환경 이미지 보존 |

## 검증 / Verification

이 문서 완료 후 다음이 모두 성공해야 [01 Day-0 설치](./01-day0-install.md)로 진행 가능:

- [x] `make ping` — 모든 호스트 SUCCESS
- [x] `make test-connection` — 그룹별 SUCCESS
- [x] `make show-inventory` — 모든 노드 표시
- [x] `make show-variables-example` — `.example` 파일 출력
- [x] `cat group_vars/all.yml` — 환경에 맞게 편집된 상태 (`.example`이 아닌 본 파일이 존재)

## FAQ

### Q1. `make ping`이 일부 호스트에서 실패합니다.
A. 가장 흔한 원인:
- SSH 키 미배포 → `ssh-copy-id`
- inventory의 `ansible_host` 또는 `ansible_user` 오타
- 방화벽 (포트 22 차단)
- 호스트 hostname을 inventory_hostname과 다르게 설정 → `set_hostname_from_inventory: true`로 통일

### Q2. ansible 명령이 매우 느려요.
A. 기본 fact 수집이 느릴 수 있음. 옵션:
```bash
# fact 캐시 활성화 (~/.ansible.cfg)
[defaults]
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts_cache
fact_caching_timeout = 86400
```

### Q3. `group_vars/all.yml`을 git에 커밋하면 안 되는 이유?
A. 이 파일은 자격증명(레지스트리 비밀번호 등)을 포함하는 게 일반적. `.gitignore`로 보호되며, 커밋 시 git 히스토리에 영구히 남음. 실수 방지를 위해 `.gitignore` 처리됨.

### Q4. NTP 서버는 어떻게 설정하나요?
A. 두 가지 옵션 (`group_vars/all.yml`):
```yaml
# 옵션 1: master1을 사내 NTP 서버로
use_local_ntp: true
cluster_network: "192.168.0.0/16"

# 옵션 2: 외부 NTP 서버
use_local_ntp: false
external_ntp_servers:
  - "pool.ntp.org"
  - "time.google.com"
```

### Q5. RHEL의 SELinux는 어떻게 처리되나요?
A. `install_os_package` role이 자동으로 permissive 모드로 변경. 운영 정책상 enforcing 유지 필요하면 K8s 공식 SELinux 정책 별도 적용.

## 관련 문서 / Related docs

- [01 Day-0 설치](./01-day0-install.md) — 다음 단계
- [README.md](../README.md) — 프로젝트 전체 개요
- [`group_vars/all.yml.example`](../group_vars/all.yml.example) — 모든 변수 상세
- [06 클러스터 리셋](./06-cluster-reset.md) — 백업 체크리스트 자세히
