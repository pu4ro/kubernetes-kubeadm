# Registry / Containerd 수정 변경점 리스트

작성: 2026-06-11. 환경: master1=192.168.135.201, master2=.202, master3=.203, VIP=.199
레지스트리: cr.makina.rocks (zot, https-only, :80=apache)

---

## A. 근본 원인 요약

1. **http/https scheme 버그** — `config_v2.toml.j2`가 mirror endpoint scheme을 `insecure_skip_verify`로 결정 → 평문 http → apache:80 404 → pause sandbox pull 실패 → 컨트롤플레인 안 뜸 → kubeadm init 타임아웃.
2. **CA 미배포** — `cr.makina.rocks-root-ca`가 master1만 설치(zot 부산물). master2/3 누락 → https 전환 후 x509.
3. **이미지 경로/태그 불일치** — 레지스트리는 이미지를 `cr-makina-rocks/...` prefix + 일부 구버전 태그(v1.34.1)로 저장. 매니페스트/kubeadm은 `registry.k8s.io/...:v1.34.7` 또는 `cr.makina.rocks/external-hub/...` 참조. config_v2(config_path="")가 certs.d override_path를 못 써서 변환 불가.
4. **containerd 버전 게이트** — containerd 2.1.4인데 게이트 `<2.2`가 config_v2(구 grpc.v1.cri)를 줌. 2.1.4는 새 cri.v1 plugin이라 config_path=certs.d 켜면 CRI image service 깨짐.
5. **이미지 미import** — master1만 `k8s-v1.34.7-custom-tags.tar` import. master2/3는 레지스트리 의존 → 위 문제로 막힘.

---

## B. 런타임 직접 수정 (3노드, 임시/검증)

| # | 노드 | 변경 | 비고 |
|---|------|------|------|
| B1 | 1/2/3 | `/etc/containerd/config.toml` mirror endpoint `http://`→`https://cr.makina.rocks` | sed |
| B2 | 2/3 | `/usr/local/share/ca-certificates/cr.makina.rocks.crt` 배포 + `update-ca-certificates` | master1 /data/cert/ca.crt에서 |
| B3 | 1 | kube-vip 이미지 retag (ctr) | push로 대체됨 |
| B4 | 1/2/3 | config.toml 백업 다수: `config.toml.bak.*`, `.bak.certsd`, `.bak2` | **정리 필요** |

## C. 레지스트리 push (영구, 레지스트리 상태)

master1 → cr.makina.rocks push (nerdctl, user mrx.dev). 경로 = 매니페스트 기대 경로:

- `cr.makina.rocks/external-hub/kubernetes/kube-apiserver:v1.34.7`
- `.../kube-controller-manager:v1.34.7`
- `.../kube-scheduler:v1.34.7`
- `.../kube-proxy:v1.34.7`
- `.../etcd:3.6.5-0`
- `.../coredns:v1.12.1`
- `.../pause:3.10.1`
- `cr.makina.rocks/external-hub/kube-vip/kube-vip:v0.7.2`

## D. 클러스터 상태 수정 (런타임)

| # | 대상 | 변경 |
|---|------|------|
| D1 | cm/kubeadm-config | imageRepository `registry.k8s.io`→`cr.makina.rocks/external-hub/kubernetes` |
| D2 | ds/kube-proxy | image → `cr.makina.rocks/external-hub/kubernetes/kube-proxy:v1.34.7` |
| D3 | deploy/coredns | image → `cr.makina.rocks/external-hub/kubernetes/coredns:v1.12.1` |

## E. Ansible 영구수정 — WSL git repo (commit bfd92bb, pushed)

| # | 파일 | 변경 |
|---|------|------|
| E1 | `roles/install_containerd/templates/config_v2.toml.j2` | mirror scheme `insecure_skip_verify`→`plain_http \| default(false)` |
| E2 | `group_vars/all.yml` | `enable_ca_certificates: true` + `ca_certificates`를 `/data/cert/ca.crt`(controller lookup) + `registry_ca_cert_path` |

## F. Ansible 영구수정 — master1 사본 (미commit, de33931 기반)

| # | 파일 | 변경 |
|---|------|------|
| F1 | `roles/install_containerd/templates/config_v2.toml.j2` | E1과 동일 (sed) |
| F2 | `group_vars/all.yml` | E2와 동일 (python) |
| F3 | 백업: `config_v2.toml.j2.bak`, `all.yml.bak` | **정리 필요** |

---

## G. 아직 안 한 영구수정 (TODO — 신규 클러스터/재현성)

- [ ] `kubeadm-init.yml` (+ 생성 템플릿) imageRepository `registry.k8s.io` → `cr.makina.rocks/external-hub/kubernetes` (현재 D1으로 런타임만 수정)
- [ ] 이미지 push를 Ansible 역할화 (local_registry 역할 활용?) — 현재 수동 nerdctl push
- [ ] WSL `/data/cert/ca.crt`가 stale(다른 CA). ansible은 **반드시 master1(.201)에서** 실행 (lookup은 controller-local)
- [ ] 백업 파일 정리 (B4, F3)
- [ ] (선택) containerd 버전 게이트 재검토: 2.1.x를 config_v3(certs.d)로 보낼지

## H. 결과 (2026-06-11)

- **3노드 클러스터 완성**: master1/2/3 전부 Ready, v1.34.7
- master2/3 ansible join 성공 (`--tags kubernetes`)
- 모든 control-plane pod Running (etcd/apiserver/controller/scheduler/kube-vip ×3, coredns, kube-proxy)
- master 추가(scale) 입증: join 로직 멱등(`'already a member'`), 신규 master는 동일 절차로 추가 가능

### 교훈 — push 누락
첫 push loop에서 `kube-controller-manager:v1.34.7`, `coredns:v1.12.1` 2개가 OK 판정인데 실제 레지스트리 미반영(grep 기반 OK 판정 오류). 재push로 해결. **push 후 반드시 `curl /v2/<img>/tags/list`로 검증할 것.**

## I. 추후 Master 추가 절차

1. inventory `[masters]`에 새 노드 추가
2. 신규 노드: OS prep + containerd (config_v2 https mirror + CA) — `ansible-playbook site.yml -i inventory.ini --limit <new> --tags base,ca-certificates,container,registry-mirror`
3. control-plane 이미지가 레지스트리에 있는지 확인(C절 경로) — 없으면 push
4. join: `ansible-playbook site.yml -i inventory.ini --tags kubernetes` (멱등, 기존 노드 skip)
5. kube-vip 이미지 레지스트리 존재 확인 (신규 master도 kube-vip static pod 가짐)

## K. 추가 수정 (한방 배포 달성)

### K1. nerdctl 부재 → 한방 배포 실패 (race 아님)
첫 `site.yml` 전체 실행시 master2/3가 `setup-docker-credentials`의 `nerdctl login`에서 죽음(nerdctl 미설치) → play1 중단 → k8s join 도달 못함. `--tags kubernetes` 재실행은 play1 스킵해서 우회됐던 것.
- **Fix**: `setup-docker-credentials`에서 nerdctl login 제거, kubelet `config.json`을 ansible이 직접 생성(`kubelet-config.json.j2`). nerdctl 의존 제거.
- 검증: reset+wipe 후 전체 `site.yml` 한방 → 3노드 Ready, failed=0

### K2. nerdctl 필수화 / buildkit 옵셔널
- `enable_nerdctl_buildkit` (묶음) → `enable_nerdctl: true`(필수) + `enable_buildkit: false`(옵셔널) 분리
- 적용: group_vars, install_containerd/tasks, install_os_package/tasks
- apt nerdctl 2.1.1 로컬 mirror서 설치 가능 확인
- 검증: 한방 배포 후 nerdctl 3노드 설치, buildkit skip, failed=0

### K3. master1 사본 ↔ WSL repo 동기화
master1 사본(de33931)이 구버전이라 WSL과 변수 구조 차이(`package_install_throttle`, `parallel_execution`). install_containerd/install_os_package tasks를 WSL로 scp + group_vars에 누락 변수 추가. reset+wipe+한방배포 재검증 통과.

## J. 미해결/확인 필요

- 레지스트리에 v1.34.7 control-plane 이미지가 원래 없던 이유(왜 v1.34.1만 sync됨) — zot sync 정책
- CNI(cilium/flannel) 설치 단계 이미지 경로 동일 문제 가능성 (CNI 이미지도 레지스트리 push 필요할 수 있음)
- 런타임 수정(B/C/D)은 ansible 영구수정(G절 TODO) 반영 전까지 재배포시 재발 가능
