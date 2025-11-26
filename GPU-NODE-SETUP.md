# GPU 노드 자동 설정 가이드

이 문서는 Kubernetes 클러스터에서 NVIDIA GPU가 있는 노드의 자동 감지 및 containerd 설정 방법을 설명합니다.

## 📋 목차

- [개요](#개요)
- [자동 감지 메커니즘](#자동-감지-메커니즘)
- [사용 방법](#사용-방법)
- [설정 확인](#설정-확인)
- [트러블슈팅](#트러블슈팅)
- [수동 설정](#수동-설정)

---

## 개요

이 프로젝트는 **자동 GPU 감지** 기능을 제공합니다. NVIDIA GPU가 있는 노드를 자동으로 감지하여 containerd를 NVIDIA Container Runtime으로 설정합니다.

### 주요 기능

- ✅ **자동 감지**: `lspci` 명령으로 NVIDIA GPU 자동 탐지
- ✅ **자동 설정**: GPU가 감지되면 containerd config.toml을 NVIDIA 런타임으로 자동 설정
- ✅ **Fact 캐싱**: 감지 결과를 fact로 저장하여 재사용
- ✅ **역할 분리**: install_os_package에서 감지, install_containerd에서 설정 적용
- ✅ **수동 제어**: 필요시 변수로 수동 제어 가능

---

## 자동 감지 메커니즘

### 1. GPU 감지 프로세스

```yaml
# install_os_package role
1. lspci | grep -i NVIDIA 실행
2. NVIDIA GPU 발견 시 has_nvidia_gpu=true 설정
3. fact를 캐시에 저장 (cacheable: yes)
```

### 2. Containerd 설정 적용

```yaml
# install_containerd role
1. has_nvidia_gpu fact 확인
2. fact가 없으면 다시 GPU 감지 수행
3. GPU 있으면: containerd_nvidia.j2 템플릿 사용
4. GPU 없으면: containerd_config.toml.j2 템플릿 사용
```

### 3. 설정 변수

| 변수 | 설명 | 기본값 | 자동 설정 |
|------|------|--------|-----------|
| `has_nvidia_gpu` | NVIDIA GPU 존재 여부 | - | ✅ 자동 감지 |
| `nvidia_runtime_enabled` | NVIDIA 런타임 활성화 여부 | - | ✅ 드라이버 설치 후 |
| `install_gpu_driver` | GPU 드라이버 설치 여부 | false | ❌ 수동 설정 |

---

## 사용 방법

### 기본 사용 (자동 감지)

별도의 설정 없이 playbook을 실행하면 자동으로 GPU를 감지합니다:

```bash
# 전체 클러스터 설치
ansible-playbook -i inventory.ini site.yml

# 특정 노드만
ansible-playbook -i inventory.ini site.yml -l worker3
```

실행 중 출력 예시:

```
TASK [install_containerd : Display containerd configuration mode] ****
ok: [worker1] => {
    "msg": "Configuring containerd with standard runtime"
}
ok: [worker2] => {
    "msg": "Configuring containerd with NVIDIA GPU runtime"
}
```

### GPU 드라이버 자동 설치

NVIDIA 드라이버까지 자동으로 설치하려면:

```bash
ansible-playbook -i inventory.ini site.yml -e "install_gpu_driver=true"
```

**요구사항:**
- RedHat/CentOS 8.x 이상
- Local repository에 NVIDIA 드라이버 파일 (`NVIDIA-Linux-x86_64-*.run`) 배치
- `driver_version` 변수 설정 (`group_vars/all.yml`)

### 특정 노드만 GPU 드라이버 설치

```bash
ansible-playbook -i inventory.ini site.yml \
  -l worker2,worker3 \
  -e "install_gpu_driver=true"
```

---

## 설정 확인

### 1. GPU 감지 확인

```bash
# 노드에서 GPU 확인
ansible -i inventory.ini all -m shell -a "lspci | grep -i NVIDIA" -b

# 출력 예시:
# worker1 | FAILED  # GPU 없음
# worker2 | SUCCESS | rc=0 >>
# 01:00.0 VGA compatible controller: NVIDIA Corporation ...
```

### 2. Containerd 설정 확인

```bash
# config.toml 확인
ansible -i inventory.ini all -m shell -a "grep -A 5 nvidia /etc/containerd/config.toml" -b

# NVIDIA runtime 설정 확인
ansible -i inventory.ini worker2 -m shell \
  -a "grep 'default_runtime_name = \"nvidia\"' /etc/containerd/config.toml" -b
```

### 3. Fact 확인

```bash
# has_nvidia_gpu fact 확인
ansible -i inventory.ini all -m setup -a "filter=ansible_local"

# 또는 ad-hoc으로 fact 조회
ansible -i inventory.ini all -m debug -a "var=has_nvidia_gpu"
```

### 4. NVIDIA 런타임 테스트

GPU가 설정된 노드에서:

```bash
# nvidia-smi 실행 확인
ssh worker2 "nvidia-smi"

# containerd에서 NVIDIA 런타임 사용 확인
ssh worker2 "nerdctl run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi"
```

---

## 트러블슈팅

### 문제 1: GPU가 감지되지 않음

**증상:**
```
TASK [install_containerd : Display containerd configuration mode]
ok: [worker2] => {
    "msg": "Configuring containerd with standard runtime"
}
```

**해결:**

```bash
# 1. 수동으로 GPU 확인
ssh worker2 "lspci | grep -i NVIDIA"

# 2. lspci 패키지 설치 확인
ssh worker2 "which lspci"

# 3. pciutils 설치
ansible -i inventory.ini worker2 -m package -a "name=pciutils state=present" -b

# 4. Playbook 재실행
ansible-playbook -i inventory.ini site.yml -l worker2 --tags container
```

### 문제 2: Containerd가 NVIDIA 설정을 사용하지 않음

**증상:**
```
Error: could not select device driver "nvidia"
```

**해결:**

```bash
# 1. nvidia-container-toolkit 설치 확인
ssh worker2 "rpm -qa | grep nvidia-container-toolkit"

# 2. 수동으로 toolkit 설치
ansible -i inventory.ini worker2 -m yum -a "name=nvidia-container-toolkit state=present" -b

# 3. containerd 재시작
ansible -i inventory.ini worker2 -m systemd -a "name=containerd state=restarted" -b
```

### 문제 3: Fact가 캐시되지 않음

**증상:**
매번 GPU 감지를 다시 수행함

**해결:**

```bash
# 1. fact cache 디렉토리 확인
ansible -i inventory.ini worker2 -m file -a "path=/etc/ansible/facts.d state=directory" -b

# 2. 수동으로 fact 설정
cat > /tmp/gpu.fact << 'EOF'
#!/bin/bash
echo '{"has_nvidia_gpu": true}'
EOF

ansible -i inventory.ini worker2 -m copy \
  -a "src=/tmp/gpu.fact dest=/etc/ansible/facts.d/gpu.fact mode=0755" -b

# 3. fact 재수집
ansible -i inventory.ini worker2 -m setup
```

### 문제 4: 드라이버 설치 실패

**증상:**
```
NVIDIA driver installation failed
```

**해결:**

```bash
# 1. Nouveau 드라이버 비활성화 확인
ssh worker2 "lsmod | grep nouveau"

# 2. 커널 개발 패키지 확인
ssh worker2 "rpm -qa | grep kernel-devel"

# 3. 재부팅 후 재시도
ansible -i inventory.ini worker2 -m reboot -b
ansible-playbook -i inventory.ini site.yml -l worker2 -e "install_gpu_driver=true"
```

---

## 수동 설정

자동 감지가 작동하지 않거나 수동 제어가 필요한 경우:

### 방법 1: Host Variables

`host_vars/worker2.yml` 생성:

```yaml
---
has_nvidia_gpu: true
```

### 방법 2: Group Variables

GPU 노드 그룹을 만들어 관리:

**inventory.ini:**
```ini
[gpu_nodes]
worker2 ansible_host=192.168.1.22
worker3 ansible_host=192.168.1.23

[gpu_nodes:vars]
has_nvidia_gpu=true
```

### 방법 3: Extra Variables

실행 시 변수로 지정:

```bash
ansible-playbook -i inventory.ini site.yml \
  -l worker2 \
  -e "has_nvidia_gpu=true" \
  -e "install_gpu_driver=true"
```

### 방법 4: Group Vars

`group_vars/gpu_nodes.yml` 생성:

```yaml
---
has_nvidia_gpu: true
install_gpu_driver: true
driver_version: "535.129.03"
```

---

## Containerd 설정 템플릿

### NVIDIA GPU Runtime Template

`roles/install_containerd/templates/containerd_nvidia.j2`에서 다음 설정이 적용됩니다:

```toml
[plugins."io.containerd.grpc.v1.cri".containerd]
  default_runtime_name = "nvidia"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
  runtime_type = "io.containerd.runc.v2"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
    BinaryName = "/usr/bin/nvidia-container-runtime"
    SystemdCgroup = true
```

### 표준 Runtime Template

`roles/install_containerd/templates/containerd_config.toml.j2`에서 기본 runc 사용

---

## 관련 파일

| 파일 | 역할 | 설명 |
|------|------|------|
| `roles/install_os_package/tasks/main.yml` | GPU 감지 | lspci로 NVIDIA GPU 감지 및 fact 설정 |
| `roles/install_containerd/tasks/main.yml` | Containerd 설정 | GPU fact 기반으로 config.toml 생성 |
| `roles/install_containerd/templates/containerd_nvidia.j2` | NVIDIA 템플릿 | NVIDIA runtime 설정 |
| `roles/install_containerd/templates/containerd_config.toml.j2` | 표준 템플릿 | 기본 runc 설정 |

---

## Kubernetes에서 GPU 사용

Containerd가 NVIDIA 런타임으로 설정되면 Kubernetes에서 GPU를 사용할 수 있습니다:

### 1. NVIDIA Device Plugin 설치 (별도)

```bash
kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml
```

### 2. GPU Pod 배포 테스트

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
spec:
  containers:
  - name: cuda
    image: nvidia/cuda:11.0-base
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
  nodeSelector:
    # GPU 노드에만 배포
    kubernetes.io/hostname: worker2
```

```bash
kubectl apply -f gpu-test.yaml
kubectl logs gpu-test
```

---

## 참고 자료

- [NVIDIA Container Toolkit 공식 문서](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
- [Containerd Configuration](https://github.com/containerd/containerd/blob/main/docs/cri/config.md)
- [Kubernetes GPU Support](https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/)

---

**마지막 업데이트**: 2025-11-25
