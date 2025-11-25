# Ansible Ad-hoc Command Utilities

이 디렉토리는 Ansible을 사용하여 ad-hoc 명령어를 쉽게 실행할 수 있는 유틸리티를 제공합니다.

## 📁 파일 구조

```
utils/
├── run-command.sh    # Shell script wrapper
├── run-command.yml   # Playbook wrapper
└── README.md         # 이 문서
```

## 🚀 사용 방법

### 1. Shell Script 방식 (run-command.sh)

간단하고 빠르게 명령어를 실행할 때 사용합니다.

#### 기본 사용법

```bash
./utils/run-command.sh "COMMAND" [TARGET_GROUP] [OPTIONS]
```

#### 파라미터 설명

| 파라미터 | 설명 | 필수 여부 | 기본값 |
|---------|------|-----------|--------|
| COMMAND | 실행할 명령어 | 필수 | - |
| TARGET_GROUP | 대상 호스트 그룹 | 선택 | all |
| OPTIONS | 추가 ansible 옵션 | 선택 | - |

#### 사용 예제

```bash
# 1. 모든 호스트에서 uptime 확인
./utils/run-command.sh "uptime"

# 2. Master 노드에서 디스크 사용량 확인
./utils/run-command.sh "df -h" masters

# 3. Worker 노드에서 메모리 확인
./utils/run-command.sh "free -m" workers

# 4. Kubelet 서비스 상태 확인
./utils/run-command.sh "systemctl status kubelet" all

# 5. 커널 버전 확인
./utils/run-command.sh "uname -r" all

# 6. Docker/Containerd 상태 확인
./utils/run-command.sh "systemctl status containerd" all

# 7. 병렬 실행 옵션 (10개 동시 실행)
./utils/run-command.sh "hostname" all "-f 10"

# 8. Verbose 모드로 실행
./utils/run-command.sh "ls -la /etc/kubernetes" masters "-vv"

# 9. Dry-run 모드 (실제 실행 없이 테스트)
./utils/run-command.sh "rm -rf /tmp/test" all "--check"

# 10. 특정 사용자로 실행
./utils/run-command.sh "whoami" all "--become-user=nginx"
```

---

### 2. Playbook 방식 (run-command.yml)

더 많은 옵션과 제어가 필요할 때 사용합니다.

#### 기본 사용법

```bash
ansible-playbook -i inventory.ini utils/run-command.yml -e "cmd='COMMAND'"
```

#### 변수 설명

| 변수 | 설명 | 필수 여부 | 기본값 |
|------|------|-----------|--------|
| cmd | 실행할 명령어 | **필수** | - |
| target_hosts | 대상 호스트 그룹 | 선택 | all |
| become_root | root 권한 사용 여부 | 선택 | true |
| gather_facts | facts 수집 여부 | 선택 | false |
| command_timeout | 명령어 타임아웃(초) | 선택 | 300 |
| ignore_errors_flag | 에러 무시 여부 | 선택 | false |
| changed_when_condition | changed 상태 조건 | 선택 | false |

#### 사용 예제

```bash
# 1. 기본 실행 - 모든 호스트에서 uptime
ansible-playbook -i inventory.ini utils/run-command.yml -e "cmd='uptime'"

# 2. 특정 호스트 그룹 지정
ansible-playbook -i inventory.ini utils/run-command.yml \
  -e "cmd='df -h'" \
  -e "target_hosts=masters"

# 3. root 권한 없이 실행
ansible-playbook -i inventory.ini utils/run-command.yml \
  -e "cmd='whoami'" \
  -e "become_root=false"

# 4. 타임아웃 설정 (600초)
ansible-playbook -i inventory.ini utils/run-command.yml \
  -e "cmd='sleep 500'" \
  -e "command_timeout=600"

# 5. 에러 무시하고 계속 진행
ansible-playbook -i inventory.ini utils/run-command.yml \
  -e "cmd='ls /nonexistent'" \
  -e "ignore_errors_flag=true"

# 6. Facts 수집 포함
ansible-playbook -i inventory.ini utils/run-command.yml \
  -e "cmd='echo \$HOSTNAME'" \
  -e "gather_facts=true"

# 7. 복잡한 명령어 실행
ansible-playbook -i inventory.ini utils/run-command.yml \
  -e "cmd='for i in {1..5}; do echo \"Count: \$i\"; done'"

# 8. 특정 호스트만 실행 (limit 사용)
ansible-playbook -i inventory.ini utils/run-command.yml \
  -e "cmd='hostname'" \
  -l master1

# 9. 여러 변수를 파일로 전달
# vars.yml 파일 생성:
# cmd: "systemctl restart kubelet"
# target_hosts: "masters"
# command_timeout: 60

ansible-playbook -i inventory.ini utils/run-command.yml -e "@vars.yml"

# 10. 태그 기반 실행 (playbook에 태그 추가 시)
ansible-playbook -i inventory.ini utils/run-command.yml \
  -e "cmd='date'" \
  --tags display
```

---

## 📝 대상 호스트 그룹

inventory.ini 파일에 정의된 그룹을 사용할 수 있습니다:

| 그룹 | 설명 |
|------|------|
| all | 모든 호스트 |
| masters | 모든 Master 노드 |
| workers | 모든 Worker 노드 |
| master1 | 첫 번째 Master 노드 |
| master[1:3] | Master 1-3 범위 |

---

## 🔧 고급 사용 예제

### 1. 여러 호스트에서 로그 수집

```bash
# Shell script 방식
./utils/run-command.sh "tail -n 100 /var/log/messages" all

# Playbook 방식
ansible-playbook -i inventory.ini utils/run-command.yml \
  -e "cmd='tail -n 100 /var/log/messages'"
```

### 2. 파일 존재 확인

```bash
# Shell script 방식
./utils/run-command.sh "test -f /etc/kubernetes/admin.conf && echo 'exists' || echo 'not found'" masters

# Playbook 방식
ansible-playbook -i inventory.ini utils/run-command.yml \
  -e "cmd='test -f /etc/kubernetes/admin.conf && echo exists || echo not found'" \
  -e "target_hosts=masters"
```

### 3. 시스템 정보 수집

```bash
# CPU 정보
./utils/run-command.sh "lscpu | grep 'Model name'" all

# 메모리 정보
./utils/run-command.sh "cat /proc/meminfo | grep MemTotal" all

# 디스크 I/O
./utils/run-command.sh "iostat -x 1 1" all
```

### 4. Kubernetes 관련 명령

```bash
# Pod 상태 확인
./utils/run-command.sh "kubectl get pods -A" master1

# Node 상태 확인
./utils/run-command.sh "kubectl get nodes" master1

# 특정 namespace의 리소스
./utils/run-command.sh "kubectl get all -n kube-system" master1
```

### 5. 패키지 정보 확인

```bash
# 설치된 패키지 버전
./utils/run-command.sh "rpm -qa | grep -i kube" all

# 특정 패키지 설치 여부
./utils/run-command.sh "which docker" all
```

---

## 🎯 실용적인 운영 시나리오

### 시나리오 1: 긴급 점검

클러스터 전체에서 디스크 사용량이 80% 이상인 호스트 찾기:

```bash
./utils/run-command.sh "df -h | awk '\$5+0 > 80 {print \$0}'" all
```

### 시나리오 2: 서비스 재시작

모든 Worker 노드에서 kubelet 재시작:

```bash
ansible-playbook -i inventory.ini utils/run-command.yml \
  -e "cmd='systemctl restart kubelet'" \
  -e "target_hosts=workers"
```

### 시나리오 3: 설정 파일 확인

특정 설정 파일의 내용 확인:

```bash
./utils/run-command.sh "grep -i 'cluster-cidr' /etc/kubernetes/manifests/kube-controller-manager.yaml" masters
```

### 시나리오 4: 네트워크 테스트

다른 노드로의 연결 테스트:

```bash
./utils/run-command.sh "ping -c 3 192.168.1.10" all
```

### 시나리오 5: 시간 동기화 확인

모든 노드의 시간 동기화 상태:

```bash
./utils/run-command.sh "timedatectl status" all
```

---

## ⚠️ 주의사항

1. **권한**: 기본적으로 root 권한(sudo)으로 실행됩니다
2. **타임아웃**: 장시간 실행되는 명령어는 timeout 설정을 조정하세요
3. **병렬 실행**: 많은 호스트에서 실행 시 `-f` 옵션으로 병렬도를 조정하세요
4. **위험한 명령어**: rm, dd 등 위험한 명령어 사용 시 주의하세요
5. **인용부호**: 명령어에 특수문자가 포함된 경우 적절히 escape 처리하세요

---

## 🐛 트러블슈팅

### 문제 1: Permission denied

```bash
# 해결: become_root를 true로 설정하거나 sudo 사용
ansible-playbook -i inventory.ini utils/run-command.yml \
  -e "cmd='cat /etc/shadow'" \
  -e "become_root=true"
```

### 문제 2: Command not found

```bash
# 해결: 전체 경로 사용
./utils/run-command.sh "/usr/local/bin/custom-command" all
```

### 문제 3: Timeout

```bash
# 해결: 타임아웃 증가
ansible-playbook -i inventory.ini utils/run-command.yml \
  -e "cmd='long-running-task'" \
  -e "command_timeout=1800"
```

### 문제 4: 특수문자 처리

```bash
# 작은따옴표 안에 명령어 넣기
./utils/run-command.sh 'echo "Hello World" > /tmp/test.txt' all

# 또는 escape 처리
./utils/run-command.sh "echo \"Hello World\"" all
```

---

## 📚 추가 리소스

- [Ansible Ad-hoc Commands 공식 문서](https://docs.ansible.com/ansible/latest/user_guide/intro_adhoc.html)
- [Ansible Shell Module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/shell_module.html)
- [Ansible Command Module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/command_module.html)

---

## 🤝 기여

개선 사항이나 버그 리포트는 프로젝트 저장소에 이슈를 등록해주세요.

---

## 📄 라이선스

이 프로젝트의 라이선스를 따릅니다.
