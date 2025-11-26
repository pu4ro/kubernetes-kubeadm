# Kubernetes Worker Node 추가 가이드

이 문서는 기존 Kubernetes 클러스터에 새로운 Worker 노드를 추가하는 방법을 설명합니다.

## 📋 목차

- [개요](#개요)
- [사전 요구사항](#사전-요구사항)
- [Worker 노드 추가 절차](#worker-노드-추가-절차)
- [사용 예제](#사용-예제)
- [고급 옵션](#고급-옵션)
- [트러블슈팅](#트러블슈팅)
- [주의사항](#주의사항)

---

## 개요

`add-worker.yml` playbook은 기존 Kubernetes 클러스터에 새로운 Worker 노드를 추가하는 자동화된 프로세스를 제공합니다.

### 주요 기능

- ✅ 자동 Join Token 생성 및 적용
- ✅ 필요한 패키지 자동 설치 (kubelet, kubeadm, kubectl)
- ✅ Containerd 및 Docker credentials 설정
- ✅ 노드 중복 join 방지
- ✅ 강제 재가입 옵션 (force_rejoin)
- ✅ 노드 상태 자동 검증
- ✅ 순차/병렬 실행 제어

### 실행 단계

1. **Phase 1**: 새 Worker 노드 준비 (패키지 설치)
2. **Phase 2**: Master에서 Join Token 생성
3. **Phase 3**: Kubernetes 패키지 설치
4. **Phase 4**: Worker 노드를 클러스터에 Join
5. **Phase 5**: 노드 상태 검증

---

## 사전 요구사항

### 1. 인프라 준비

새로운 Worker 노드가 다음 조건을 만족해야 합니다:

- [ ] OS 설치 완료 (RedHat/CentOS 8.x 또는 Ubuntu 20.04+)
- [ ] SSH 접근 가능 (root 또는 sudo 권한)
- [ ] Master 노드와 네트워크 연결
- [ ] 최소 사양: CPU 2 core, RAM 2GB, Disk 20GB

### 2. Inventory 파일 업데이트

새 Worker 노드를 `inventory.ini`에 추가:

```ini
[masters]
master1 ansible_host=192.168.1.10

[workers]
worker1 ansible_host=192.168.1.21
worker2 ansible_host=192.168.1.22
worker3 ansible_host=192.168.1.23  # 새로 추가된 노드
```

### 3. 필수 변수 확인

`group_vars/all.yml`에서 다음 변수가 설정되어 있는지 확인:

```yaml
kubernetes_version: "1.28.0"  # 기존 클러스터와 동일한 버전
```

---

## Worker 노드 추가 절차

### 방법 1: 기본 실행 (권장)

모든 Worker 노드를 순차적으로 추가:

```bash
ansible-playbook -i inventory.ini add-worker.yml
```

### 방법 2: 특정 노드만 추가

`-l` 옵션으로 특정 호스트만 대상으로 지정:

```bash
# 단일 노드 추가
ansible-playbook -i inventory.ini add-worker.yml -l worker3

# 여러 노드 추가
ansible-playbook -i inventory.ini add-worker.yml -l worker3,worker4

# 패턴 사용
ansible-playbook -i inventory.ini add-worker.yml -l "worker[3:5]"
```

### 방법 3: 병렬 실행

여러 노드를 동시에 추가:

```bash
ansible-playbook -i inventory.ini add-worker.yml -e "worker_add_serial=0"
```

### 방법 4: 강제 재가입

이미 join된 노드를 reset하고 다시 추가:

```bash
ansible-playbook -i inventory.ini add-worker.yml -e "force_rejoin=true" -l worker3
```

---

## 사용 예제

### 예제 1: 새 Worker 노드 1개 추가

```bash
# 1. inventory.ini에 새 노드 추가
cat >> inventory.ini << EOF
worker3 ansible_host=192.168.1.23
EOF

# 2. SSH 접근 확인
ansible -i inventory.ini worker3 -m ping

# 3. Worker 추가 실행
ansible-playbook -i inventory.ini add-worker.yml -l worker3

# 4. 노드 확인
kubectl get nodes
```

### 예제 2: 여러 Worker 노드 동시 추가

```bash
# inventory.ini 업데이트
[workers]
worker1 ansible_host=192.168.1.21
worker2 ansible_host=192.168.1.22
worker3 ansible_host=192.168.1.23
worker4 ansible_host=192.168.1.24
worker5 ansible_host=192.168.1.25

# 새로운 3개 노드만 추가
ansible-playbook -i inventory.ini add-worker.yml -l worker3,worker4,worker5
```

### 예제 3: 특정 태그만 실행

```bash
# 패키지 설치만 실행
ansible-playbook -i inventory.ini add-worker.yml -l worker3 --tags packages

# 컨테이너 런타임만 설치
ansible-playbook -i inventory.ini add-worker.yml -l worker3 --tags container
```

### 예제 4: Verbose 모드로 디버깅

```bash
ansible-playbook -i inventory.ini add-worker.yml -l worker3 -vv
```

### 예제 5: 문제가 있는 노드 재가입

```bash
# 노드 상태가 NotReady이거나 문제가 있을 때
ansible-playbook -i inventory.ini add-worker.yml -l worker3 -e "force_rejoin=true"
```

---

## 고급 옵션

### 옵션 변수

| 변수 | 설명 | 기본값 | 예제 |
|------|------|--------|------|
| `force_rejoin` | 이미 join된 노드 강제 재가입 | false | `-e "force_rejoin=true"` |
| `worker_add_serial` | 동시 실행할 노드 수 | 100% | `-e "worker_add_serial=2"` |
| `kubernetes_version` | 설치할 Kubernetes 버전 | 1.28.0 | `-e "kubernetes_version=1.29.0"` |

### Serial 실행 제어

```bash
# 순차 실행 (한 번에 하나씩)
ansible-playbook -i inventory.ini add-worker.yml -e "worker_add_serial=1"

# 2개씩 동시 실행
ansible-playbook -i inventory.ini add-worker.yml -e "worker_add_serial=2"

# 모든 노드 동시 실행
ansible-playbook -i inventory.ini add-worker.yml -e "worker_add_serial=0"

# 50% 동시 실행
ansible-playbook -i inventory.ini add-worker.yml -e "worker_add_serial=50%"
```

### Check 모드 (Dry-run)

실제 변경 없이 실행 계획만 확인:

```bash
ansible-playbook -i inventory.ini add-worker.yml -l worker3 --check
```

---

## 트러블슈팅

### 문제 1: 노드가 이미 join되어 있음

**증상:**
```
FAILED! => {"msg": "Node is already joined. Use -e 'force_rejoin=true' to reset and rejoin"}
```

**해결:**
```bash
# 강제 재가입 옵션 사용
ansible-playbook -i inventory.ini add-worker.yml -l worker3 -e "force_rejoin=true"
```

### 문제 2: Join token이 만료됨

**증상:**
```
error: [discovery] Failed to request cluster-info: the server has asked for the client to provide credentials
```

**해결:**
Token은 자동으로 새로 생성되므로 playbook을 다시 실행:
```bash
ansible-playbook -i inventory.ini add-worker.yml -l worker3
```

### 문제 3: 노드가 NotReady 상태

**증상:**
```bash
kubectl get nodes
NAME      STATUS     ROLE    AGE   VERSION
worker3   NotReady   <none>  1m    v1.28.0
```

**해결:**
```bash
# 1. CNI 플러그인 확인
kubectl get pods -n kube-system | grep flannel

# 2. 노드 상세 정보 확인
kubectl describe node worker3

# 3. Kubelet 로그 확인
ansible -i inventory.ini worker3 -m shell -a "journalctl -u kubelet -n 50"

# 4. 재가입 시도
ansible-playbook -i inventory.ini add-worker.yml -l worker3 -e "force_rejoin=true"
```

### 문제 4: 패키지 설치 실패

**증상:**
```
Failed to install kubelet-1.28.0
```

**해결:**
```bash
# 1. Repository 확인
ansible -i inventory.ini worker3 -m shell -a "yum repolist" -b

# 2. 버전 확인
ansible -i inventory.ini worker3 -m shell -a "yum list available kubelet --showduplicates" -b

# 3. 정확한 버전 지정
ansible-playbook -i inventory.ini add-worker.yml -l worker3 -e "kubernetes_version=1.28.2"
```

### 문제 5: Master와 연결 불가

**증상:**
```
Failed to connect to API server
```

**해결:**
```bash
# 1. 네트워크 연결 확인
ansible -i inventory.ini worker3 -m shell -a "ping -c 3 192.168.1.10"

# 2. 방화벽 확인
ansible -i inventory.ini worker3 -m shell -a "firewall-cmd --list-all" -b

# 3. API 서버 포트 확인
ansible -i inventory.ini worker3 -m shell -a "telnet 192.168.1.10 6443"
```

### 문제 6: Containerd 서비스 실패

**증상:**
```
Failed to start containerd service
```

**해결:**
```bash
# 1. Containerd 상태 확인
ansible -i inventory.ini worker3 -m shell -a "systemctl status containerd" -b

# 2. Containerd 재설치
ansible-playbook -i inventory.ini add-worker.yml -l worker3 --tags container -e "force_rejoin=true"

# 3. 수동 시작
ansible -i inventory.ini worker3 -m shell -a "systemctl restart containerd" -b
```

---

## 주의사항

### ⚠️ 중요 사항

1. **버전 호환성**: 새 Worker 노드의 Kubernetes 버전은 기존 클러스터와 동일하거나 ±1 minor 버전 이내여야 합니다
   ```bash
   # 클러스터 버전 확인
   kubectl version --short

   # 버전 지정하여 추가
   ansible-playbook -i inventory.ini add-worker.yml -l worker3 -e "kubernetes_version=1.28.0"
   ```

2. **네트워크 요구사항**:
   - Master 노드 API Server (6443) 접근 가능
   - Pod Network CIDR과 충돌하지 않는 노드 IP
   - CNI 플러그인 포트 (Flannel: 8472/UDP)

3. **리소스 요구사항**:
   - 최소: CPU 2 core, RAM 2GB
   - 권장: CPU 4 core, RAM 8GB
   - Disk: 최소 20GB (container images용)

4. **보안**:
   - SSH key 기반 인증 권장
   - Sudo 권한 필요
   - Firewall 설정 확인

5. **백업**:
   - Worker 추가 전 etcd 백업 권장
   - 기존 워크로드 영향 최소화

---

## 검증 체크리스트

Worker 노드 추가 후 다음 사항을 확인하세요:

```bash
# 1. 노드 상태 확인
kubectl get nodes
# 새 노드가 Ready 상태인지 확인

# 2. 노드 상세 정보
kubectl describe node worker3
# Conditions가 모두 정상인지 확인

# 3. Kubelet 버전 확인
kubectl get nodes -o wide
# VERSION 컬럼이 클러스터와 일치하는지 확인

# 4. Pod 스케줄링 테스트
kubectl run test-pod --image=nginx --replicas=3
kubectl get pods -o wide
# 새 노드에도 Pod이 스케줄링 되는지 확인

# 5. 정리
kubectl delete deployment test-pod
```

---

## 참고 자료

### 관련 파일

- `add-worker.yml` - Worker 추가 playbook
- `inventory.ini` - 호스트 인벤토리
- `group_vars/all.yml` - 전역 변수
- `roles/install_os_package/` - 패키지 설치 role
- `roles/install_containerd/` - Containerd 설치 role
- `roles/install_kubernetes/` - Kubernetes 설치 role

### 유용한 명령어

```bash
# 노드 목록 확인
kubectl get nodes -o wide

# 특정 노드의 Pod 확인
kubectl get pods --all-namespaces -o wide --field-selector spec.nodeName=worker3

# 노드에서 Pod 제거 (drain)
kubectl drain worker3 --ignore-daemonsets --delete-emptydir-data

# 노드 스케줄링 재개
kubectl uncordon worker3

# 노드 레이블 추가
kubectl label nodes worker3 node-role.kubernetes.io/worker=worker

# 노드 삭제 (필요시)
kubectl delete node worker3
```

---

## 문의 및 지원

문제가 발생하거나 도움이 필요한 경우 프로젝트 저장소에 이슈를 등록해주세요.

---

**마지막 업데이트**: 2025-11-25
