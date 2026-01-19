# Update Node IP Role

Kubernetes 설정 파일의 IP 주소를 변경하는 역할입니다.

> **주의**: 이 role은 설정 파일을 변경합니다. 실제 시스템 IP 변경은 사용자가 직접 수행해야 합니다.

## 주요 기능

- **데이터 보존**: `--force-new-cluster` 플래그를 사용하여 etcd 데이터를 유지하면서 IP 변경
- **인증서 재생성**: IP가 인증서 SAN에 포함된 경우 자동 재생성
- **자동 서비스 재시작**: kubelet 캐시 문제 자동 해결

## 업데이트 대상 파일

- `/etc/kubernetes/manifests/etcd.yaml`
- `/etc/kubernetes/manifests/kube-apiserver.yaml`
- `/etc/kubernetes/manifests/kube-controller-manager.yaml`
- `/etc/kubernetes/manifests/kube-scheduler.yaml`
- `/etc/kubernetes/admin.conf`
- `/etc/kubernetes/kubelet.conf`
- `/etc/kubernetes/controller-manager.conf`
- `/etc/kubernetes/scheduler.conf`
- `/var/lib/kubelet/config.yaml`
- `/etc/hosts`
- `~/.kube/config`

## 사용법

```bash
# 1. 시스템 IP 먼저 변경 (예: netplan)
sudo vi /etc/netplan/00-installer-config.yaml
sudo netplan apply

# 2. inventory.ini 업데이트
vi inventory.ini  # ansible_host를 새 IP로 변경

# 3. role 실행 (데이터 보존)
make update-ip-with-certs OLD_IP=192.168.1.100 NEW_IP=192.168.1.200 HOST=master1

# 또는 Ansible 직접 실행
ansible-playbook -i inventory.ini update-node-ip.yml \
  -e 'old_ip=192.168.1.100' \
  -e 'new_ip=192.168.1.200' \
  -e 'regenerate_certs=true' \
  --limit master1
```

## 변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `old_ip` | (필수) | 변경 전 IP |
| `new_ip` | `ansible_host` | 변경 후 IP |
| `update_etc_hosts` | `true` | /etc/hosts 업데이트 여부 |
| `regenerate_certs` | `false` | 인증서 재생성 여부 |
| `force_new_etcd_cluster` | `true` | etcd를 새 클러스터로 시작 (데이터 보존) |
| `reset_etcd_data` | `false` | etcd 데이터 초기화 (경고: 모든 데이터 손실!) |
| `restart_services` | `true` | 서비스 재시작 여부 |

## 작동 방식

### 1단계: 파일 업데이트
- kubelet 중지
- 모든 컨테이너/pod 제거 (kubelet 캐시 초기화)
- manifest, kubeconfig 파일의 IP 교체

### 2단계: 인증서 재생성 (선택)
- 기존 인증서 백업 및 삭제
- 새 IP로 인증서 재생성 (etcd, apiserver)
- 도메인 SAN 자동 포함 (api_domain, hostname.domain_suffix)

### 3단계: etcd 마이그레이션
- `--force-new-cluster` 플래그로 etcd 시작
- etcd가 새 IP로 클러스터 재구성 (기존 데이터 유지)
- 플래그 제거 후 정상 모드로 재시작

### 4단계: 서비스 시작
- kubelet 시작
- control plane pod 대기 (30초)

## 중요 사항

### force-new-cluster vs reset-etcd-data

| 방법 | 데이터 | 사용 시점 |
|------|--------|----------|
| `force_new_etcd_cluster=true` | **보존** | 일반적인 IP 변경 (권장) |
| `reset_etcd_data=true` | **손실** | force-new-cluster 실패 시 |

### 테스트 결과

```
# IP 변경 전
IP: 192.168.135.42
Deployments: nginx-test

# IP 변경 후
IP: 192.168.135.41
Deployments: nginx-test  ← 데이터 보존됨!
```

### 주의사항

1. **단일 마스터 전용**: 이 role은 단일 마스터 클러스터를 위해 설계되었습니다.
2. **시스템 IP 먼저 변경**: role 실행 전에 시스템 IP를 먼저 변경해야 합니다.
3. **inventory 업데이트**: 새 IP로 inventory를 업데이트해야 합니다.
4. **인증서 재생성 권장**: IP가 인증서에 포함되어 있으므로 `regenerate_certs=true` 권장.
