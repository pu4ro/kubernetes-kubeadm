# kubernetes-kubeadm 기능 명세 (SPEC)

> kubeadm 기반 Kubernetes 클러스터를 Ansible로 설치·운영하는 저장소의 기능 명세서.
> 코드 기준으로 작성되었으며, 변수 세부는 [`group_vars/all.yml.example`](../group_vars/all.yml.example)를 함께 참조하세요.

## 1. 개요
- **목적**: kubeadm 기반 Kubernetes 클러스터 자동 설치/운영. 단일 마스터·HA(다중 마스터)·온라인/오프라인(사내망) 지원.
- **대상 OS**: Ubuntu/Debian, RHEL/Rocky/CentOS (`ansible_os_family` 분기).
- **런타임**: containerd (버전 자동 감지 → v2/v3 설정 포맷 분기).
- **CNI**: flannel(기본) 또는 cilium 선택(`network_plugin`).
- **기본 K8s 버전**: `1.34.1` (kubeadm v1beta4 API 템플릿).

## 2. 인벤토리 그룹 (`inventory.ini`)
| 그룹 | 용도 |
|---|---|
| `[masters]` | 컨트롤플레인 노드 |
| `[workers]` | 워커 노드 |
| `[installs]` | 마스터 전용 패키지(make, helmfile 등) 설치 대상 |
| `[pre-installs]` | 사전 설치 단계 대상 |
| `[all:vars]` | 접속 사용자(`ansible_user`), `become`, SSH 인증 등 |

## 3. 메인 설치 플레이북 `site.yml` (단계별)
실행: `ansible-playbook -i inventory.ini site.yml` 또는 `make install`

1. **Phase 1 — 시스템 준비 (hosts: all)**
   `setup_rhel_repo` → `setup_ubuntu_repo` → `set_hostname` → `configure_etc_hosts` → `install_ca_certificates` → `configure_sysctl` → `install_os_package` → `setup_containerd_disk` → `install_containerd` → `configure_registry_mirror` → `install_nvidia_driver` → `fix_nvidia_toolkit_path` → `setup-docker-credentials`
   - 병렬도: `parallel_execution.system_preparation`로 `linear`/`free` 전략 선택.
2. **Phase 2 — Kubernetes 설치**
   - 마스터: `serial: 1`(순차, etcd 경쟁 방지) — `install_kubernetes`
   - 워커: `serial: 100%`(병렬, `kubernetes_installation` 전략) — `install_kubernetes`
3. **Phase 3 — CNI**: `network_plugin`에 따라 `install_flannel` 또는 `install_cilium`.
4. **Phase 4 — 마스터 스케줄링**: `allow_master_scheduling` 시 `remove_master_taint`(단일노드).
5. **Phase 4.5 — GPU 라벨링**: `label_gpu_nodes` (GPU 감지 시 `gpu=on`).
6. **Phase 5 — 인증서 연장**: `extend_k8s_certs`(10년).
7. **Phase 6 — CoreDNS hosts**: `configure_coredns_hosts`.
8. **Phase 7 — OIDC**: `configure_oidc_apiserver`(`serial: 1`).

## 4. Role별 기능

### 4.1 시스템 준비
- **configure_sysctl**: 커널 모듈 로드(br_netfilter, overlay, ip_vs*, nf_conntrack) + 부팅 자동로드, RHEL SELinux/firewalld 비활성화, `k8s_sysctl_params` 적용, swap off + fstab 제거. (성능: 항목별 reload 대신 마지막 `sysctl --system` 일괄 적용)
- **install_os_package**: 크로스플랫폼 패키지 설치 핵심.
  - 커스텀 Ubuntu 저장소(24.04는 기존 소스 비활성화), 공식 k8s/containerd 저장소(pkgs.k8s.io / download.docker.com) 옵션.
  - containerd: 패키지 핀 설치(hold) 또는 GitHub 바이너리 직접 설치(`enable_containerd_binary_install`).
  - kubelet/kubeadm/kubectl 버전 핀 + hold/versionlock.
  - 공통/선택 패키지(nerdctl·buildkit, helmfile, master 전용 make), GPU 감지(`has_nvidia_gpu`), apt 대량작업 `throttle`(=`package_install_throttle` 변수).
- **install_containerd**: containerd **설정** 전담(설치는 install_os_package).
  - RHEL podman 충돌 패키지 제거, systemd LimitNPROC/NOFILE, 버전 감지 후 `config_v2/v3.toml.j2` 배포.
  - CONTAINERD_NAMESPACE=k8s.io, 소켓 `wait_for` + crictl CRI 검증(실패 시 강제 재시작/실패 처리), insecure registry certs.d 구성.
- **setup_containerd_disk**: containerd 데이터 전용 디스크 13단계 셋업(검증→포맷(FS 없을 때만)→UUID fstab→mount→검증). 멱등.
- **setup_ubuntu_repo / setup_rhel_repo**: 오프라인/사내 APT·YUM 저장소(RHEL 다중 저장소 priority 지원).
- **install_ca_certificates**: 사내 CA 인증서 시스템 신뢰 저장소 설치(inline/url/path).
- **set_hostname / configure_etc_hosts**: 인벤토리 기반 호스트네임, `/etc/hosts`에 노드+레지스트리+커스텀 매핑.

### 4.2 Kubernetes 설치 (`install_kubernetes`)
- kubelet 시작, `kubeadm-init.yaml.j2` 생성, manifests 준비.
- **단일/HA 분기**: 단일 `kubeadm init`, HA `--upload-certs`; kube-vip(`kube-vip.yaml.j2`) 또는 도메인 기반(`api_domain`) 엔드포인트.
- 추가 마스터 조인: 토큰/CA 해시/certificate-key 생성·전파, 이전 마스터 Ready 폴링 후 join(실패 시 rescue로 VIP/매니페스트 정리 + `kubeadm reset`).
- 워커 조인: join → 등록 검증 → `node-role.kubernetes.io/worker` 라벨.
- 마스터 bashrc PATH + kubectl 자동완성/alias(로그인 사용자 + root, loop로 구성).

### 4.3 네트워크(CNI)
- **install_flannel**: `kube-flannel.yml.j2` 적용 + Ready 폴링.
- **install_cilium**: Cilium CLI 설치(온라인/오프라인), `cilium install`(hubble, encryption, kubeProxyReplacement, 추가 helm values, 커스텀 이미지 repo), 멱등(기존 DaemonSet 감지), `cilium status --wait`.

### 4.4 레지스트리/인증
- **configure_registry_mirror**: containerd `certs.d` 미러 구성(외부→사내 미러 매핑, docker.io 특수 처리), 변경 시 재시작 후 소켓 `wait_for`. 자격증명은 `docker_registries`에서 파생.
- **setup-docker-credentials**: nerdctl login + containerd registry auth 구성.
- **configure_oidc_apiserver**: kube-apiserver static pod 매니페스트 백업 후 OIDC 플래그(`--oidc-*`) 및 선택적 PodNodeSelector admission 추가, `/healthz` 폴링으로 재기동 확인/검증.

> 참고: 컨테이너 레지스트리 구동이 필요한 경우 스크립트 기반 도구(`scripts/manage-registry.sh`, `make registry-start`)를 사용합니다. (기존 `local_registry` Ansible 역할은 제거됨)

### 4.5 GPU
- **install_nvidia_driver**: `.run` 드라이버 설치(옵션, reboot 처리).
- **fix_nvidia_toolkit_path**: containerd config의 NVIDIA toolkit 경로 보정. 게이트 변수 `enable_fix_nvidia_toolkit_path`.
- **label_gpu_nodes**: GPU 노드 라벨링.

### 4.6 클러스터 마무리/운영
- **remove_master_taint**: 단일노드용 마스터 스케줄 허용.
- **extend_k8s_certs**: 인증서 10년 연장(`k8s_cert_extend.sh.j2`), kubelet/컴포넌트 재시작 핸들러.
- **configure_coredns_hosts**: CoreDNS Corefile에 레지스트리/호스트 매핑 주입, kube-dns Ready 대기.
- **validate_cluster**: 설치 후 검증 — DNS 확인, Pod↔Pod(nginx 2개), egress 외부통신 테스트(`kubectl wait`/`curl`/`wget`).

## 5. 보조 플레이북
| 파일 | 기능 |
|---|---|
| `add-worker.yml` | 신규 워커 추가(준비→조인→라벨), `worker_add_serial`로 병렬도 제어 |
| `check-and-add-workers.yml` | 미조인 워커 자동 감지 후 일괄 추가 |
| `reset.yml` / `reset_cluster.yml` | 클러스터/노드 리셋(`reset_k8s_cluster`, `serial:1`) |
| `update-node-ip.yml` / `update-ha-node-ip.yml` | 노드 IP 변경 반영(`update_node_ip`: etcd 멤버 업데이트, kubelet/containerd 재시작 핸들러) |
| `validation.yml` | `validate_cluster` 단독 실행 |
| `cleanup-rook-ceph.yml` | Rook-Ceph 리소스 정리(CRD 삭제 전 K8s API 필요) |

## 6. 주요 변수 그룹 (`group_vars/all.yml`, 8그룹)
1. **클러스터 기본**: `kubernetes_version`, `pod_subnet`, `service_subnet`, `extend_k8s_certificates`
2. **HA/도메인**: `master_ha`, `kube_vip_*`, `enable_domain_communication`, `api_domain`, `domain_suffix`, `extra_cert_sans`, `etcd_domain_config`
3. **네트워크/CNI**: `network_plugin`, `cilium_*`
4. **런타임/레지스트리**: `containerd_*`, `pause_image`, `enable_registry_mirror`+`registry_mirror_*`, `insecure_registries`, `enable_containerd_disk`+`containerd_disk_*`, `enable_custom_image_repository`/`k8s_image_repository`
5. **시스템/호스트/시간**: `set_timezone`, `k8s_sysctl_params`, NTP, `configure_etc_hosts`, `parallel_execution`(+`package_install_throttle`)
6. **GPU/NVIDIA**: `enable_nvidia_driver_install`, `nvidia_driver_*`, `enable_nvidia_containerd_config`, `enable_fix_nvidia_toolkit_path`, `enable_gpu_node_labels`
7. **인증/보안**: `enable_oidc_apiserver`+`oidc_*`, `enable_pod_node_selector`, `enable_ca_certificates`+`ca_certificates`, `docker_login_required`+`docker_registries`
8. **OS 패키지/오프라인 저장소**: `enable_rhel_repos`+`rhel_repos`, `enable_ubuntu_repo`+`ubuntu_repo_*`, `*_packages`, `enable_official_k8s_repo`, `enable_official_containerd_repo`, `enable_containerd_binary_install`+`runc_version`

## 7. 실행/태그
- 전체 설치: `make install` / `ansible-playbook -i inventory.ini site.yml`
- 검증: `make validate`, HA etcd: `make check-etcd-health`
- 부분 실행 태그 예: `base`, `container`, `kubernetes`, `networking`, `registry-mirror`, `oidc-apiserver`, `setup-containerd-disk`, `k8s-official-repo`, `nvidia`/`fix-nvidia-toolkit-path`, `coredns-hosts`, `k8s-certs`, `docker-credentials`, `ca-certificates`

## 8. 멱등성·속도 메커니즘
- 대부분 작업이 `stat`/`grep`/`creates`/`when` 가드로 멱등(이미 조인/포맷/설정 시 skip).
- 병렬화: `parallel_execution` play 전략(`free`/`linear`) + apt `throttle`.
- 준비대기: 고정 `pause` 대신 `wait_for`/`until` 폴링 위주(happy-path 고정 sleep 제거).
- 버전 핀: containerd/kubelet/kubeadm/kubectl 모두 핀 + hold/versionlock.
