# Kubernetes 클러스터 자동 설치 (Ansible)

<!-- en-start -->
> **English Quick Start (full doc is Korean — auto-translate recommended).**
>
> Ansible-based Kubernetes installer. Supports Kubernetes 1.27.x – 1.34.x
> (kubeadm v1beta3/v1beta4 auto-selected) and containerd 1.7.x – 2.2.x.
> Features: Flannel/Cilium CNI, HA via kube-vip or domain-based endpoint,
> OIDC, containerd registry mirror, NVIDIA GPU, online + offline installs.
>
> ```bash
> # 1. inventory.ini: list masters/workers/installs
> # 2. cp group_vars/all.yml.example group_vars/all.yml  # edit secrets
> make ping            # SSH check
> make install         # full install
> make validate        # cluster health check
> ```
>
> See **Runbooks** below for day-2 operations and incident response.
<!-- en-end -->

Ansible을 사용한 Kubernetes 클러스터 자동 배포 도구. Flannel/Cilium CNI, HA, OIDC 인증, 레지스트리 미러, GPU, 오프라인 설치 등 운영 환경 기능을 모두 지원합니다.

## 개요

- **지원 Kubernetes:** 1.27.x – 1.34.x (kubeadm v1beta3/v1beta4 자동 분기). 권장 기본값 `1.34.1`.
- **지원 containerd:** 1.7.x – 2.2.x (config v2/v3 자동 분기). 권장 기본값 `2.2.0`.
- **OS:** Ubuntu 20.04 / 22.04, RHEL/Rocky 8 / 9.
- **토폴로지:** 단일 마스터 / HA 3-마스터 (kube-vip 또는 도메인 기반).
- **CNI:** Flannel(기본) / Cilium.
- **부가 기능:** OIDC 인증, containerd registry mirror, NVIDIA GPU 자동 설정, 사용자 CA, 오프라인 설치.
- **Role 수:** 27개 (`roles/`).

## 호환 버전

| 항목 | 지원 범위 | 권장 기본값 | 자동 처리 |
|---|---|---|---|
| Kubernetes | 1.27.x – 1.34.x | `1.34.1` | ≤1.30 → kubeadm v1beta3, ≥1.31 → v1beta4 |
| containerd | 1.7.x – 2.2.x | `2.2.0` | <2.2 → config v2 (`sandbox_image`), ≥2.2 → config v3 (`pinned_images.sandbox`) |
| pause image | 3.9 ~ 3.10.1 | `3.10.1` | k8s 버전에 맞춰 자동 선택 |

> 다른 버전이 필요하면 `group_vars/all.yml`에서 `kubernetes_version`, `containerd_version`을 직접 지정하세요.

## 빠른 시작

세 가지 시나리오 중 하나를 선택. 모든 시나리오의 검증 명령은 `make validate`입니다.

### 시나리오 A — 단일 마스터 (가장 간단)

```bash
# 1. inventory.ini 작성 (masters 1대, workers N대)
# 2. 설정 복사 및 편집
cp group_vars/all.yml.example group_vars/all.yml
# group_vars/all.yml에서: master_ha=false, kube_vip_*, oidc/registry 등 환경에 맞게 조정

make ping                  # SSH 연결 테스트
make install               # 전체 설치 (10–25분)
make validate              # 노드/Pod/DNS/Pod간 통신 검증
```

문제가 생기면 → `journalctl -u kubelet -f` / [runbooks/recovery.md](./runbooks/recovery.md).

### 시나리오 B — 오프라인 설치 (사내망)

```bash
# 사전: RHEL ISO/디렉토리 미러, registry mirror 호스트 준비
cp group_vars/all.yml.example group_vars/all.yml
# 조정: enable_rhel_repos=true, repo_url.*, enable_registry_mirror=true,
#       registry_mirror_host/user/password, k8s_image_repository, pause_image

make install
make validate
```

Cilium을 오프라인으로 쓰려면 추가로 `network_plugin: cilium`, `cilium_offline_install: true`, `cilium_image_repository`를 설정.

### 시나리오 C — HA 3-마스터

```bash
# inventory.ini의 [masters]에 master1/master2/master3 모두 등록
cp group_vars/all.yml.example group_vars/all.yml
# 조정: master_ha=true
# 옵션 1 (kube-vip): kube_vip_address: 192.168.1.10 추가
# 옵션 2 (도메인 기반): enable_domain_communication=true, api_domain DNS 사전 구성

make install
make check-etcd-health     # etcd 3 멤버 모두 healthy 확인
make validate
```

## 변수 가이드

세부 변수와 코멘트는 [`group_vars/all.yml.example`](./group_vars/all.yml.example)을 참조하세요. 그룹 구성:

| # | 그룹 | 주요 키워드 |
|---|---|---|
| 1 | 클러스터 기본 | `kubernetes_version`, `pod_subnet`, `extend_k8s_certificates` |
| 2 | HA / 도메인 통신 | `master_ha`, `kube_vip_*`, `enable_domain_communication`, `api_domain` |
| 3 | 네트워크 / CNI | `network_plugin`, `cilium_*` |
| 4 | 컨테이너 런타임 / 레지스트리 | `containerd_*`, `enable_registry_mirror`, `registry_mirror_*`, `enable_containerd_disk` |
| 5 | 시스템 / 호스트 / 시간 | `set_timezone`, `k8s_sysctl_params`, `use_local_ntp`, `parallel_execution` |
| 6 | GPU / NVIDIA | `enable_nvidia_driver_install`, `enable_nvidia_containerd_config`, `enable_gpu_node_labels` |
| 7 | 인증 / 보안 | `enable_oidc_apiserver`, `oidc_*`, `enable_pod_node_selector`, `enable_ca_certificates` |
| 8 | OS 패키지 / 오프라인 저장소 | `repo_url`, `enable_rhel_repos`, `rhel_repos`, `*_packages` |

> NVIDIA GPU Operator를 별도로 사용하는 경우 관련 변수는 본 예제 파일에 포함되어 있지 않습니다. 별도 Helm 차트로 설치하세요.

## Makefile 명령

전체 명령은 `make help`. 자주 쓰는 것만 발췌:

| 카테고리 | 명령 | 설명 |
|---|---|---|
| 연결 | `make ping` | 모든 호스트 SSH 연결 테스트 |
| 설치 | `make install` | 전체 설치 (site.yml) |
| 설치 | `make install-step1` / `step2` / `step3` | 시스템 준비 / K8s / CNI 단계 분리 |
| 검증 | `make validate` | 노드/Pod/DNS/Pod간 통신/외부 연결 검증 |
| 검증 | `make check-cluster` | 노드·Pod 상태 quick view |
| 검증 | `make check-etcd-health` / `check-etcd-members` | HA etcd 클러스터 상태 |
| Worker | `make check-and-add-workers` | 미등록 Worker 자동 감지·조인 |
| 운영 | `make tag-registry-mirror` / `tag-oidc-apiserver` / `tag-nvidia` | 특정 기능만 재적용 |
| IP 변경 | `make update-ip` / `update-ha-ip` | 노드 IP 변경 (HOST/OLD_IP/NEW_IP 필요) |
| 인증서 | `make tag-certs` | 인증서 10년 연장 |
| 리셋 | `make reset` / `reset-workers` | 클러스터 초기화 (확인 필요) |
| 디버그 | `make cmd-host HOST=master1 CMD="..."` | 특정 호스트 명령 실행 |

## Runbook

운영 절차는 위험도별 3개 파일로 정리:

| 위험도 | 파일 | 다루는 시나리오 | 소요 시간 |
|---|---|---|---|
| Low | [runbooks/daily-ops.md](./runbooks/daily-ops.md) | Worker 추가, 상태 확인, validation | 5–30분 |
| Medium | [runbooks/risky-ops.md](./runbooks/risky-ops.md) | IP 변경, 인증서 갱신, 오프라인 ↔ 온라인 전환 | 30–90분 |
| High | [runbooks/recovery.md](./runbooks/recovery.md) | NotReady, etcd 복구, CNI 장애, registry 장애, OIDC 장애, 전체 reset (롤백 포함) | 가변 |

## 트러블슈팅 (5건)

| 증상 | 진단 명령 | 일반적 원인 / 해결 |
|---|---|---|
| 노드 NotReady | `kubectl describe node <n>` + `journalctl -u kubelet -f` | CNI Pod 미준비, swap, containerd 미동작. [recovery.md §노드 NotReady](./runbooks/recovery.md) |
| Worker join 실패 | `kubeadm token create --print-join-command` 재시도 + master에서 6443 포트 점검 | 토큰 만료, 방화벽, hostname 충돌 |
| 이미지 pull 실패 | `nerdctl pull <image>` 단독 실행 / `cat /etc/containerd/certs.d/<host>/hosts.toml` | registry 인증 누락 → `make tag-docker-credentials`, mirror 미설정 → `make tag-registry-mirror` |
| 인증서 만료 | `kubeadm certs check-expiration` | `extend_k8s_certificates=true` 후 `make tag-certs`. [risky-ops.md §인증서 갱신](./runbooks/risky-ops.md) |
| 포트 막힘 | `ss -tlnp \| grep -E '6443\|10257\|10259\|2379\|2380'` | k8s 1.20+에서 scheduler/controller는 `10259`/`10257`. Cilium은 `4240/4244`, VXLAN은 `8472/udp` |

## Documentation map

| 문서 | 상태 | 권장 사용 |
|---|---|---|
| [README.md](./README.md) | **canonical** | 시작점 (이 파일) |
| [`group_vars/all.yml.example`](./group_vars/all.yml.example) | **canonical** | 변수 참조 |
| [runbooks/](./runbooks/) | **canonical** | 운영/장애 대응 |
| [ADD-WORKER-GUIDE.md](./ADD-WORKER-GUIDE.md) | legacy (deep-dive) | Worker 추가 상세 — 일반 절차는 daily-ops.md |
| [CONTAINERD-CUSTOM-PATH.md](./CONTAINERD-CUSTOM-PATH.md) | legacy (deep-dive) | `containerd_data_base_dir` 상세 |
| [MAKEFILE-GUIDE.md](./MAKEFILE-GUIDE.md) | legacy (deep-dive) | Makefile 명령 사용 예 — 요약은 위 표 |
| [k8s-setup-README.md](./k8s-setup-README.md) | legacy (deletable) | 구버전 설치 가이드. canonical README로 대체됨 |

## 검증 명령 부록 (CI 도입 시 활용)

문서·변수·playbook 일관성을 수동 점검할 때:

```bash
# 1) 문서에서 호출하는 make 타깃이 실제로 존재하는지
for t in $(grep -hoE 'make [a-z][a-z0-9-]+' README.md runbooks/*.md | awk '{print $2}' | sort -u); do
  grep -q "^${t}:" Makefile || echo "MISSING: $t"
done

# 2) 문서에서 언급한 *.yml playbook이 존재하는지
grep -rhoE '[a-z][a-z0-9_-]+\.yml' README.md runbooks/ | sort -u | while read y; do
  [ -f "$y" ] || echo "MISSING playbook: $y"
done

# 3) 내부 마크다운 링크 점검
grep -rhoE '\]\(\.?/?[^)]+\.md[^)]*\)' README.md runbooks/ | sed 's/.*](\(.*\))/\1/' | while read p; do
  [ -f "$p" ] || echo "BROKEN link: $p"
done

# 4) playbook 문법
make lint
```

## 라이선스 / 기여

내부 운영 도구. 라이선스 정책은 별도 문의.
