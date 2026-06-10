# Ansible 개선안: 멱등성 유지 및 설치 최적화

전체 롤(26개) 스캔 결과 기반 개선 제안. 우선순위는 **P1(재실행 시 실패/부작용) → P2(불필요한 changed 보고) → P3(설치 속도/효율)** 순.

---

## 1. 요약

| 분류 | 건수 | 대표 사례 |
|------|------|-----------|
| 재실행 시 실패하는 작업 (P1) | 5 | `validate_cluster`의 `kubectl run` — 두 번째 실행에서 AlreadyExists 실패 |
| 무조건 재시작/재실행 (P1) | 4 | `setup-docker-credentials`의 containerd/kubelet 무조건 restart |
| `changed_when` 누락 (P2) | 40+ | shell/command 진단·조회 작업이 매번 changed 보고 |
| 항상 changed 되는 label/taint (P2) | 3 | `kubectl label --overwrite` + `changed_when: true` |
| 설치 비효율 (P3) | 8 | apt `cache_valid_time: 0` 강제 갱신, `creates` 없는 다운로드/압축해제, 고정 `pause` |

---

## 2. P1 — 멱등성 위반 (재실행 시 실패 또는 부작용)

### 2.1 validate_cluster: 검증 파드 생성이 재실행에서 실패

`roles/validate_cluster/tasks/main.yml:61,96,102,149`

`kubectl run validate-dns` 등은 파드가 이미 존재하면 두 번째 실행에서 실패한다.
이전 실행이 중간에 끊기면 cleanup이 안 돼 다음 검증 전체가 막힌다.

```yaml
# 개선: 생성 전 기존 파드 제거를 보장하거나, AlreadyExists를 성공 처리
- name: Run DNS validation pod
  command: kubectl run validate-dns --image=... --restart=Never
  register: dns_pod_create
  failed_when:
    - dns_pod_create.rc != 0
    - "'AlreadyExists' not in dns_pod_create.stderr"
```

추가: cleanup 작업(`kubectl delete pod`, line 89, 141, 173)은 `changed_when: false`로.
검증 자체는 클러스터 단위 작업이므로 `run_once: true` + `delegate_to: "{{ groups['masters'][0] }}"` 권장 (3절 효율 항목과 연계).

### 2.2 setup-docker-credentials: 무조건 서비스 재시작

`roles/setup-docker-credentials/tasks/main.yml:57-65,118-125`

`docker_registries`만 정의돼 있으면 설정 변경 여부와 무관하게 containerd/kubelet을 매번 재시작한다. 운영 클러스터에서 재실행 시 불필요한 워크로드 중단 발생.

```yaml
# 개선: 템플릿/copy 변경 시에만 재시작 (handler 패턴)
- name: Deploy containerd registry config
  template: ...
  register: registry_config
  notify: restart containerd   # handlers/main.yml 추가

- name: Restart kubelet if config changed
  systemd: { name: kubelet, state: restarted }
  when: nerdctl_config is changed
```

### 2.3 configure_coredns_hosts: kubectl create/replace 무방비

`roles/configure_coredns_hosts/tasks/main.yml:81-86,99`

- `kubectl create`/`replace`가 재실행 보호 없음 → `kubectl apply` 또는 `create --dry-run=client -o yaml | kubectl apply -f -` 패턴으로 교체.
- line 99의 CoreDNS 파드 삭제는 ConfigMap 실변경 시에만: `when: configmap_update is changed`.

### 2.4 extend_k8s_certs: 매 실행마다 인증서 재생성

`roles/extend_k8s_certs/tasks/main.yml:39`

스크립트가 만료 검사 없이 매번 인증서를 재발급한다. API 서버 재시작 동반 → 재실행 비용 큼.

```yaml
# 개선: 만료 잔여일 검사 후 임계값 이하일 때만 실행
- name: Check apiserver cert expiry days
  shell: |
    openssl x509 -enddate -noout -in /etc/kubernetes/pki/apiserver.crt \
      | cut -d= -f2 | xargs -I{} date -d {} +%s
  register: cert_expiry_epoch
  changed_when: false

- name: Extend certs
  shell: /tmp/k8s_cert_extend.sh ...
  when: ((cert_expiry_epoch.stdout | int) - (ansible_date_time.epoch | int)) < (3650 * 86400 * 0.9)
```

### 2.5 install_containerd: CRI 실패 시 무한 재시작 가능성 — 검증 결과 비해당

`roles/install_containerd/tasks/main.yml:187-213` 확인 결과: 재시작 1회 → 재검증 → 여전히 실패 시 명시적 `fail` 태스크 존재. 루프 아님. **조치 불필요** (초기 스캔 보고 과장).

---

## 3. P2 — 불필요한 changed 보고 (멱등성 신뢰도) — 적용 완료

적용 시 확인된 사항: 3.1 표의 일부 항목(`configure_sysctl` modprobe, `install_nvidia_driver` 진단, `install_containerd` 버전 조회, cilium/flannel daemonset 조회)은 이미 `changed_when: false` 보유 — 초기 스캔 보고가 구식이었음. 실제 수정 범위는 커밋 diff 참조.

`--check` 모드와 changed 카운트를 신뢰할 수 있어야 운영 중 드라이런 검증이 가능하다.

### 3.1 읽기 전용 shell/command에 `changed_when: false` 일괄 추가

40건 이상. 대표 위치:

| 파일 | 라인 | 작업 |
|------|------|------|
| `roles/install_kubernetes/tasks/main.yml` | 10, 67, 72, 77, 232, 281 | kubectl get / token·hash 생성 / completion |
| `roles/install_cilium/tasks/main.yml` | 59, 107 | daemonset 조회, cilium status |
| `roles/install_flannel/tasks/main.yml` | 21, 30, 44 | daemonset/pod 조회, kubectl apply |
| `roles/install_nvidia_driver/tasks/main.yml` | 6, 23, 88, 152 | lspci, nvidia-smi, lsmod |
| `roles/update_node_ip/tasks/*.yml` | 다수 | crictl rm, rm -f, replace 루프 |

규칙:
- 조회/진단 → `changed_when: false`
- 정리(delete/rm) → `changed_when: false` (멱등 정리)
- 상태 변경 명령 → 출력 기반 changed 판정 (아래 3.2)

### 3.2 kubectl label/taint: 출력 기반 changed 판정

`roles/label_gpu_nodes/tasks/main.yml:28` (`changed_when: true`), `roles/remove_master_taint/tasks/main.yml:25,37`

```yaml
- name: Label GPU node
  command: kubectl label node {{ node }} {{ label }} --overwrite
  register: label_result
  changed_when: "'labeled' in label_result.stdout"
  # kubectl은 변경 없으면 'not labeled' / 변경 시 'labeled' 출력
```

`remove_master_taint`의 `ignore_errors: true`(line 28, 40)는 실제 오류를 가린다.
"taint not found"는 성공 처리, 그 외는 실패하도록 `failed_when`으로 교체.

### 3.3 install_kubernetes: kubeadm init 가드 강화

`roles/install_kubernetes/tasks/main.yml:40,44`

현재 `kubectl get nodes` 실패 여부로만 init 여부를 판단 → API 서버가 일시 다운이면 기존 클러스터에 재-init 시도 위험.

```yaml
# 개선: admin.conf 존재를 1차 가드로
- name: Check existing cluster
  stat: { path: /etc/kubernetes/admin.conf }
  register: kubeadm_initialized

- name: Initialize cluster
  command: kubeadm init --config=/root/kubeadm-init.yml
  when: not kubeadm_initialized.stat.exists
```

검증 결과: worker join은 이미 `kubelet.conf` stat 가드 존재 (line 216-224, 양호). HA master join 블록에는 가드가 없어 재실행 중 일시 오류 시 rescue의 `kubeadm reset`이 정상 노드를 초기화할 위험 → `admin.conf` stat 가드 추가.

---

## 4. P3 — 설치 최적화 (속도/효율) — 적용 완료

적용 시 확인된 사항: 4.4의 validate_cluster run_once는 `validation.yml`이 이미 `hosts: masters[0]`이므로 불필요. cilium `creates` 이중 가드와 nvidia wget→get_url 모듈 전환은 기존 가드가 동작 중이므로 보류. remove_master_taint의 kubectl 호출 통합도 fallback 조건이 이미 효율적이라 보류.

### 4.1 apt 캐시 강제 갱신 — 현황 확인 결과 대부분 양호

검증 결과 `roles/install_os_package/tasks/main.yml:62-70`의 `cache_valid_time: 0`은 이미 `when: ubuntu_repo_created is changed`로 게이트되어 있어 repo 변경 시에만 실행됨 (정상). `setup_ubuntu_repo`도 동일 패턴. **추가 조치 불필요** — 단, 신규 apt 작업 추가 시 메인 캐시 갱신(line 158-160)의 `cache_valid_time: 3600` 패턴을 따를 것.

### 4.2 다운로드/압축해제에 `creates` 가드 (방어적 보강)

- `roles/install_cilium/tasks/main.yml:21-33` — get_url/unarchive 모두 `when: not cilium_cli_installed.stat.exists` 가드 있음 (검증 완료). `creates: /usr/local/bin/cilium`은 stat 변수와 작업 사이 드리프트를 막는 이중 안전장치로만 가치 있음 — 선택 사항.
- `roles/install_os_package/tasks/main.yml:172-202` — containerd 바이너리 tarball 다운로드에 `creates` 또는 `checksum` 추가.
- `roles/install_nvidia_driver/tasks/main.yml:115-121` — shell+wget 대신 `get_url` 모듈 (creates 가드는 이미 있음, 모듈 전환은 체크섬·재개 지원 이점).

### 4.3 고정 pause → 조건 기반 대기

- `roles/update_node_ip/tasks/main.yml:213,314`, `ha_single_master.yml:310,353` — `pause: seconds: 30` → `until`/`retries` 또는 `wait_for`. etcd/API가 빨리 뜨면 즉시 진행, 느리면 더 기다림.
- `roles/install_containerd/tasks/main.yml:196` — `pause: seconds: 10` → `wait_for: path=/run/containerd/containerd.sock` (line 167-169에 이미 동일 패턴 존재, 재사용).
- `roles/install_flannel/tasks/main.yml:44-49` — pod grep 루프 → `kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s` 한 줄로 대체.

### 4.4 검증/조회 작업 run_once 적용

- `roles/validate_cluster` 전체 — 클러스터 단위 검증이므로 `run_once: true` + 첫 master delegate. 노드 수 N배 절약.
- `roles/remove_master_taint/tasks/main.yml:4-14` — control-plane/master 노드 조회 2회 kubectl 호출 → 1회 통합.

### 4.5 install_containerd: 재시작·daemon_reload 조건화

`roles/install_containerd/tasks/main.yml:129-140`

- `daemon_reload` → `when: systemd_service_file is changed`
- 무조건 restart → 기존 `notify: restart containerd` handler(line 111, 122에 이미 존재)로 통일.

### 4.6 install_os_package: helm plugin 정리 조건화

`roles/install_os_package/tasks/main.yml:281,387-390` — `helm plugin remove secrets`가 매번 실행. `helm plugin list` 결과 register 후 존재 시에만 실행.

---

## 5. 이미 잘 된 패턴 (유지)

- `install_ca_certificates`, `configure_etc_hosts`, `configure_oidc_apiserver` — 위반 없음. 신규 롤 작성 시 참고 기준.
- `setup_rhel_repo` — backup `creates` 가드, 변경 시에만 `yum clean` (모범 사례).
- `install_containerd`의 template + `notify` handler 패턴, `setup_containerd_disk`의 `filesystem force: no`.
- `set_hostname`의 사실(fact) 비교 조건, `install_nvidia_driver`의 `meta: end_host` 조기 종료.

---

## 6. 적용 순서 제안

1. **P1 5건** — 재실행 안전성 확보 (validate_cluster, docker-credentials, coredns_hosts, extend_k8s_certs, kubeadm init 가드). 운영 클러스터 재실행 리스크 직접 제거.
2. **P2 changed_when 일괄 정리** — 기계적 수정, 롤 단위 커밋. 이후 `ansible-playbook --check`가 의미 있는 드라이런이 됨.
3. **P3 최적화** — apt 캐시, creates 가드, pause 제거, run_once. 설치/재실행 시간 단축.

검증 기준: 동일 인벤토리로 site.yml 2회 연속 실행 → 2회차 `changed=0`, `failed=0` (idempotence test). CI에 추가 가능:

```bash
ansible-playbook -i inventory.ini site.yml
ansible-playbook -i inventory.ini site.yml | tee second-run.log
grep -E 'changed=[1-9]|failed=[1-9]' second-run.log && exit 1 || true
```
