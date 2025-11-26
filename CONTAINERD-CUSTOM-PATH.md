# Containerd 사용자 지정 데이터 경로 설정 가이드

이 문서는 containerd의 데이터 디렉토리를 호스트별로 분리하여 관리하는 방법을 설명합니다.

## 📋 목차

- [개요](#개요)
- [설정 방법](#설정-방법)
- [사용 예제](#사용-예제)
- [경로 구조](#경로-구조)
- [마이그레이션](#마이그레이션)
- [트러블슈팅](#트러블슈팅)
- [주의사항](#주의사항)

---

## 개요

기본적으로 containerd는 `/var/lib/containerd`를 데이터 디렉토리로 사용합니다. 이 기능을 사용하면 각 호스트별로 별도의 경로를 지정할 수 있습니다.

### 주요 기능

- ✅ **호스트별 분리**: 각 노드마다 `{기본경로}/{hostname}` 형식으로 데이터 저장
- ✅ **유연한 설정**: group_vars에서 간단히 설정 가능
- ✅ **대용량 디스크 활용**: 별도 마운트된 디스크를 containerd 데이터용으로 사용
- ✅ **자동 디렉토리 생성**: playbook 실행 시 자동으로 디렉토리 생성
- ✅ **기본값 지원**: 설정하지 않으면 기본 경로 사용

### 사용 시나리오

1. **대용량 디스크 활용**: `/data` 등 별도 마운트된 대용량 디스크를 containerd용으로 사용
2. **NFS/공유 스토리지**: 각 노드별 하위 디렉토리로 분리하여 관리
3. **디스크 용량 관리**: 시스템 디스크와 데이터 디스크를 분리하여 용량 관리
4. **백업/복원**: 호스트별로 데이터가 분리되어 있어 백업/복원이 용이

---

## 설정 방법

### 1. group_vars 설정

`group_vars/all.yml` 파일을 편집합니다:

```yaml
# Container Runtime
containerd_version: "1.7.6"

# Containerd Data Directory Configuration
containerd_data_base_dir: "/data/containerd"  # 원하는 기본 경로 설정
```

**옵션:**

| 설정값 | 결과 | 설명 |
|--------|------|------|
| `/data/containerd` | `/data/containerd/{hostname}` | 사용자 지정 경로 사용 |
| `/mnt/storage/containerd` | `/mnt/storage/containerd/{hostname}` | 외부 스토리지 사용 |
| 빈 문자열 (`""`) | `/var/lib/containerd` | 기본 경로 사용 |
| 주석 처리 | `/var/lib/containerd` | 기본 경로 사용 |

### 2. Playbook 실행

설정 후 playbook을 실행하면 자동으로 적용됩니다:

```bash
# 전체 클러스터에 적용
ansible-playbook -i inventory.ini site.yml

# 특정 노드만 적용
ansible-playbook -i inventory.ini site.yml -l worker3

# containerd role만 실행
ansible-playbook -i inventory.ini site.yml --tags container
```

### 3. 확인

설정이 정상적으로 적용되었는지 확인:

```bash
# config.toml에서 root 경로 확인
ansible -i inventory.ini all -m shell -a "grep '^root =' /etc/containerd/config.toml" -b

# 디렉토리 존재 확인
ansible -i inventory.ini all -m shell -a "ls -ld /data/containerd/*" -b

# containerd 서비스 상태 확인
ansible -i inventory.ini all -m shell -a "systemctl status containerd" -b
```

---

## 사용 예제

### 예제 1: 기본 사용 (/data/containerd)

**설정:**
```yaml
# group_vars/all.yml
containerd_data_base_dir: "/data/containerd"
```

**결과:**
```
master1: /data/containerd/master1
master2: /data/containerd/master2
worker1: /data/containerd/worker1
worker2: /data/containerd/worker2
```

**실행:**
```bash
ansible-playbook -i inventory.ini site.yml
```

### 예제 2: NFS 공유 스토리지 사용

**시나리오**: NFS가 `/mnt/nfs`에 마운트되어 있고, 각 노드별로 하위 디렉토리 사용

**설정:**
```yaml
# group_vars/all.yml
containerd_data_base_dir: "/mnt/nfs/containerd"
```

**NFS 마운트** (사전 작업):
```bash
# 모든 노드에 NFS 마운트
ansible -i inventory.ini all -m mount \
  -a "path=/mnt/nfs src=nfs-server:/export/containerd fstype=nfs state=mounted" -b
```

**결과:**
```
/mnt/nfs/containerd/
├── master1/
├── master2/
├── worker1/
└── worker2/
```

### 예제 3: 대용량 디스크를 /data에 마운트

**시나리오**: 1TB SSD를 `/data`에 마운트하여 containerd 전용으로 사용

**준비:**
```bash
# 1. 디스크 파티션 및 포맷 (예: /dev/sdb)
ansible -i inventory.ini all -m shell -a "mkfs.ext4 /dev/sdb" -b

# 2. /data 디렉토리 생성
ansible -i inventory.ini all -m file -a "path=/data state=directory" -b

# 3. fstab에 추가하여 영구 마운트
ansible -i inventory.ini all -m mount \
  -a "path=/data src=/dev/sdb fstype=ext4 state=mounted" -b
```

**설정:**
```yaml
# group_vars/all.yml
containerd_data_base_dir: "/data/containerd"
```

**실행:**
```bash
ansible-playbook -i inventory.ini site.yml
```

### 예제 4: 노드 그룹별 다른 경로 사용

**시나리오**: Master는 기본 경로, Worker는 `/data/containerd` 사용

**Master 그룹 설정** (`group_vars/masters.yml`):
```yaml
# masters.yml
containerd_data_base_dir: ""  # 기본 경로 사용
```

**Worker 그룹 설정** (`group_vars/workers.yml`):
```yaml
# workers.yml
containerd_data_base_dir: "/data/containerd"
```

**결과:**
```
master1: /var/lib/containerd (기본)
master2: /var/lib/containerd (기본)
worker1: /data/containerd/worker1
worker2: /data/containerd/worker2
```

### 예제 5: 기본 경로로 되돌리기

**설정:**
```yaml
# group_vars/all.yml
containerd_data_base_dir: ""  # 빈 문자열 또는 주석 처리
# containerd_data_base_dir: "/data/containerd"  # 주석 처리
```

**실행:**
```bash
ansible-playbook -i inventory.ini site.yml --tags container
```

---

## 경로 구조

### 디렉토리 구조

사용자 지정 경로를 설정하면 다음과 같은 구조로 생성됩니다:

```
{containerd_data_base_dir}/
├── master1/
│   ├── io.containerd.content.v1.content/
│   ├── io.containerd.metadata.v1.bolt/
│   ├── io.containerd.runtime.v1.linux/
│   ├── io.containerd.runtime.v2.task/
│   ├── io.containerd.snapshotter.v1.overlayfs/
│   └── tmpmounts/
├── master2/
│   └── (동일 구조)
├── worker1/
│   └── (동일 구조)
└── worker2/
    └── (동일 구조)
```

### config.toml 설정

**사용자 지정 경로 사용 시:**
```toml
# /etc/containerd/config.toml
root = "/data/containerd/worker1"
state = "/run/containerd"
```

**기본 경로 사용 시:**
```toml
# /etc/containerd/config.toml
root = "/var/lib/containerd"
state = "/run/containerd"
```

---

## 마이그레이션

기존 `/var/lib/containerd` 데이터를 새 경로로 마이그레이션하는 방법:

### 방법 1: 수동 마이그레이션 (권장)

```bash
# 1. containerd 중지
ansible -i inventory.ini all -m systemd -a "name=containerd state=stopped" -b

# 2. 데이터 복사
ansible -i inventory.ini all -m shell \
  -a "rsync -av /var/lib/containerd/ /data/containerd/\$(hostname)/" -b

# 3. group_vars/all.yml 수정
# containerd_data_base_dir: "/data/containerd"

# 4. playbook 실행하여 config.toml 업데이트
ansible-playbook -i inventory.ini site.yml --tags container

# 5. containerd 시작
ansible -i inventory.ini all -m systemd -a "name=containerd state=started" -b

# 6. 확인
ansible -i inventory.ini all -m shell -a "nerdctl images" -b

# 7. 문제없으면 기존 데이터 삭제
ansible -i inventory.ini all -m shell -a "rm -rf /var/lib/containerd.bak" -b
```

### 방법 2: Playbook을 이용한 자동 마이그레이션

마이그레이션용 playbook 생성 (`migrate-containerd-data.yml`):

```yaml
---
- name: Migrate Containerd Data
  hosts: all
  become: yes
  vars:
    new_data_dir: "/data/containerd"

  tasks:
    - name: Stop containerd
      systemd:
        name: containerd
        state: stopped

    - name: Create backup directory
      file:
        path: /var/lib/containerd.bak
        state: directory

    - name: Backup current data
      shell: rsync -av /var/lib/containerd/ /var/lib/containerd.bak/
      when: lookup('fileglob', '/var/lib/containerd/*') | length > 0

    - name: Create new data directory
      file:
        path: "{{ new_data_dir }}/{{ inventory_hostname }}"
        state: directory
        owner: root
        group: root
        mode: '0755'

    - name: Copy data to new location
      shell: rsync -av /var/lib/containerd/ "{{ new_data_dir }}/{{ inventory_hostname }}/"
      when: lookup('fileglob', '/var/lib/containerd/*') | length > 0

    - name: Update config.toml
      lineinfile:
        path: /etc/containerd/config.toml
        regexp: '^root\s*='
        line: 'root = "{{ new_data_dir }}/{{ inventory_hostname }}"'
        backup: yes

    - name: Start containerd
      systemd:
        name: containerd
        state: started

    - name: Verify containerd is running
      command: nerdctl images
      register: nerdctl_check
      changed_when: false

    - name: Display migration status
      debug:
        msg: "Migration successful for {{ inventory_hostname }}"
      when: nerdctl_check.rc == 0
```

**실행:**
```bash
ansible-playbook -i inventory.ini migrate-containerd-data.yml
```

---

## 트러블슈팅

### 문제 1: Containerd가 시작하지 않음

**증상:**
```
Failed to start containerd.service
```

**해결:**
```bash
# 1. 로그 확인
ansible -i inventory.ini worker1 -m shell -a "journalctl -u containerd -n 50" -b

# 2. 디렉토리 권한 확인
ansible -i inventory.ini worker1 -m shell -a "ls -ld /data/containerd/worker1" -b

# 3. 디렉토리가 없으면 수동 생성
ansible -i inventory.ini worker1 -m file \
  -a "path=/data/containerd/worker1 state=directory owner=root group=root mode=0755" -b

# 4. containerd 재시작
ansible -i inventory.ini worker1 -m systemd -a "name=containerd state=restarted" -b
```

### 문제 2: 디스크 용량 부족

**증상:**
```
no space left on device
```

**해결:**
```bash
# 1. 디스크 사용량 확인
ansible -i inventory.ini all -m shell -a "df -h /data" -b

# 2. containerd 데이터 크기 확인
ansible -i inventory.ini all -m shell \
  -a "du -sh /data/containerd/\$(hostname)" -b

# 3. 불필요한 이미지 정리
ansible -i inventory.ini all -m shell -a "nerdctl system prune -af" -b

# 4. 사용하지 않는 컨테이너 정리
ansible -i inventory.ini all -m shell -a "nerdctl container prune -f" -b
```

### 문제 3: 이미지가 보이지 않음

**증상:**
마이그레이션 후 `nerdctl images`에 이미지가 없음

**해결:**
```bash
# 1. config.toml의 root 경로 확인
ansible -i inventory.ini worker1 -m shell -a "grep '^root =' /etc/containerd/config.toml" -b

# 2. 실제 데이터 디렉토리 확인
ansible -i inventory.ini worker1 -m shell -a "ls -la /data/containerd/worker1" -b

# 3. 데이터가 있으면 containerd 재시작
ansible -i inventory.ini worker1 -m systemd -a "name=containerd state=restarted" -b

# 4. namespace 확인
ansible -i inventory.ini worker1 -m shell -a "nerdctl --namespace k8s.io images" -b
```

### 문제 4: Kubernetes Pod이 시작하지 않음

**증상:**
```
Failed to create pod sandbox
```

**해결:**
```bash
# 1. containerd 상태 확인
ansible -i inventory.ini worker1 -m shell -a "systemctl status containerd" -b

# 2. kubelet 재시작
ansible -i inventory.ini worker1 -m systemd -a "name=kubelet state=restarted" -b

# 3. Pod 상태 확인
kubectl get pods -A -o wide

# 4. Pod 이벤트 확인
kubectl describe pod <pod-name> -n <namespace>
```

### 문제 5: 마운트 포인트가 사라짐

**증상:**
재부팅 후 `/data`가 마운트되지 않아 containerd 실패

**해결:**
```bash
# 1. fstab에 마운트 설정 추가
ansible -i inventory.ini all -m mount \
  -a "path=/data src=/dev/sdb fstype=ext4 state=present" -b

# 2. 수동 마운트
ansible -i inventory.ini all -m mount \
  -a "path=/data src=/dev/sdb fstype=ext4 state=mounted" -b

# 3. containerd 재시작
ansible -i inventory.ini all -m systemd -a "name=containerd state=restarted" -b
```

---

## 주의사항

### ⚠️ 중요 사항

1. **디스크 마운트 확인**
   - 사용자 지정 경로 사용 시 해당 디스크가 올바르게 마운트되어 있는지 확인
   - `/etc/fstab`에 영구 마운트 설정 권장

2. **충분한 용량 확보**
   - Containerd 데이터는 계속 증가하므로 충분한 디스크 공간 확보
   - 최소 100GB 이상 권장 (워크로드에 따라 다름)

3. **백업 계획**
   - 마이그레이션 전 기존 데이터 백업 필수
   - 정기적인 백업 계획 수립

4. **권한 설정**
   - 디렉토리는 root:root 소유, 0755 권한 필요
   - SELinux가 활성화된 경우 컨텍스트 설정 필요

5. **서비스 중단 시간**
   - 마이그레이션 중 containerd 서비스 중지 필요
   - 운영 중인 Pod에 영향을 줄 수 있으므로 계획적으로 진행

6. **네트워크 스토리지 사용 시**
   - NFS 등 네트워크 스토리지 사용 시 성능 저하 가능
   - 로컬 SSD 사용 권장

---

## 관련 파일

| 파일 | 역할 |
|------|------|
| `group_vars/all.yml` | 전역 변수 설정 (containerd_data_base_dir) |
| `roles/install_containerd/tasks/main.yml` | 디렉토리 생성 및 설정 적용 |
| `roles/install_containerd/templates/containerd_config.toml.j2` | 표준 config.toml 템플릿 |
| `roles/install_containerd/templates/containerd_nvidia.j2` | NVIDIA GPU용 config.toml 템플릿 |

---

## 참고 자료

- [Containerd Configuration](https://github.com/containerd/containerd/blob/main/docs/ops.md)
- [Containerd Storage](https://github.com/containerd/containerd/blob/main/docs/snapshotters/README.md)

---

**마지막 업데이트**: 2025-11-25
