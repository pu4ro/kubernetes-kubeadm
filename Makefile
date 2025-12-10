.PHONY: help install install-step1 install-step2 install-step3 install-all
.PHONY: reset ping check-cluster
.PHONY: tag-sysctl tag-packages tag-container tag-kubernetes tag-networking
.PHONY: tag-certs tag-coredns tag-harbor tag-docker-credentials
.PHONY: limit-master limit-workers
.PHONY: command cmd-all cmd-masters cmd-workers cmd-installs cmd-host
.PHONY: check-workers add-workers check-and-add-workers
.PHONY: registry-start registry-stop registry-restart registry-status registry-remove registry-logs registry-init
.PHONY: nfs-init nfs-install nfs-start nfs-stop nfs-restart nfs-status nfs-reload nfs-show-exports nfs-add-export nfs-remove
.PHONY: ubuntu-repo-init ubuntu-repo-setup ubuntu-repo-remove ubuntu-repo-status ubuntu-repo-update-sources
.PHONY: apache-repo-install apache-repo-start apache-repo-stop apache-repo-restart apache-repo-status apache-repo-remove

.DEFAULT_GOAL := help

# 변수 설정
INVENTORY := inventory.ini
PLAYBOOK := site.yml
RESET_PLAYBOOK := reset_cluster.yml
ADD_WORKER_PLAYBOOK := add-worker.yml
CHECK_ADD_WORKERS_PLAYBOOK := check-and-add-workers.yml

##@ 일반 명령어

help: ## 사용 가능한 Make 명령어 목록 표시
	@echo ""
	@echo "\033[1;34m╔══════════════════════════════════════════════════════════════════════════════╗\033[0m"
	@echo "\033[1;34m║              Kubernetes 클러스터 자동화 배포 도구 (Ansible)                ║\033[0m"
	@echo "\033[1;34m╚══════════════════════════════════════════════════════════════════════════════╝\033[0m"
	@echo ""
	@echo "\033[1m사용법:\033[0m"
	@echo "  make \033[36m<target>\033[0m"
	@echo ""
	@echo "\033[1m빠른 시작 예제:\033[0m"
	@echo "  \033[32mmake ping\033[0m              # 호스트 연결 테스트"
	@echo "  \033[32mmake install\033[0m           # 전체 클러스터 설치"
	@echo "  \033[32mmake check-cluster\033[0m     # 클러스터 상태 확인"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf ""} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-28s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1;33m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@echo ""
	@echo "\033[1m유용한 팁:\033[0m"
	@echo "  • 특정 호스트 명령: \033[36mmake cmd-host HOST=\"master1\" CMD=\"uptime\"\033[0m"
	@echo "  • 모든 호스트 명령:  \033[36mmake cmd-all CMD=\"df -h\"\033[0m"
	@echo "  • 레지스트리 시작:   \033[36mmake registry-init && make registry-start\033[0m"
	@echo ""
	@echo "\033[1m더 많은 정보:\033[0m"
	@echo "  README.md를 참조하거나 https://github.com/your-repo 방문"
	@echo ""

ping: ## 모든 호스트 SSH 연결 테스트 (inventory.ini 검증)
	@echo "==> 모든 호스트 연결 테스트 중..."
	ansible all -i $(INVENTORY) -m ping

check-cluster: ## 클러스터 노드 및 Pod 상태 확인 (nodes, pods -A)
	@echo "==> 클러스터 상태 확인 중..."
	ansible masters -i $(INVENTORY) -m shell -a "kubectl get nodes -o wide"
	@echo ""
	@echo "==> 시스템 Pod 상태:"
	ansible masters -i $(INVENTORY) -m shell -a "kubectl get pods -A"

##@ 설치 명령어

install: ## 전체 클러스터 설치 (site.yml 전체 실행)
	@echo "==> 전체 Kubernetes 클러스터 설치 시작..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK)

install-step1: ## Phase 1: 시스템 준비 (sysctl + packages + containerd)
	@echo "==> Phase 1: 시스템 준비 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags sysctl,packages,container

install-step2: ## Phase 2: K8s 설치 (kubeadm init/join)
	@echo "==> Phase 2: Kubernetes 설치 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags kubernetes

install-step3: ## Phase 3: CNI 플러그인 (Flannel)
	@echo "==> Phase 3: 네트워크 플러그인 설치 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags networking

install-all: install-step1 install-step2 install-step3 ## 단계별 순차 설치 (step1 → step2 → step3)
	@echo "==> 모든 설치 단계 완료!"

install-minimal: ## 최소 구성 (sysctl + containerd + k8s + flannel)
	@echo "==> 최소 구성 설치 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags sysctl,container,kubernetes,networking

install-production: ## 프로덕션 설치 (전체 기능 + 인증서 + CoreDNS)
	@echo "==> 프로덕션 전체 설치 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags sysctl,packages,container,docker-credentials,kubernetes,networking,k8s-certs,coredns-hosts

##@ Tag 기반 설치

tag-sysctl: ## Sysctl 설정 (커널 파라미터, swap 비활성화, 모듈 로드)
	@echo "==> Sysctl 설정 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags sysctl

tag-packages: ## OS 패키지 설치 (필수 시스템 패키지)
	@echo "==> OS 패키지 설치 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags packages

tag-container: ## Containerd 설치 및 설정 (GPU 자동 감지 포함)
	@echo "==> 컨테이너 런타임 설치 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags container

tag-docker-credentials: ## 레지스트리 인증 (nerdctl login + containerd 설정)
	@echo "==> 레지스트리 인증 설정 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags docker-credentials

tag-kubernetes: ## K8s 클러스터 초기화 및 노드 조인
	@echo "==> Kubernetes 설치 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags kubernetes

tag-networking: ## Flannel CNI 플러그인 배포
	@echo "==> 네트워크 플러그인 설치 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags networking

tag-certs: ## K8s 인증서 10년 연장 (API server, controller 등)
	@echo "==> 인증서 연장 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags k8s-certs

tag-coredns: ## CoreDNS 호스트 설정 (레지스트리 도메인 추가)
	@echo "==> CoreDNS 설정 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags coredns-hosts

tag-harbor: ## Harbor 프로젝트 자동 생성
	@echo "==> Harbor 프로젝트 설정 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags harbor-setup

tag-scheduling: ## Master 노드 Pod 스케줄링 허용 (taint 제거)
	@echo "==> Master 노드 스케줄링 설정 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags scheduling

tag-local-registry: registry-start ## [DEPRECATED] registry-start 사용 권장

##@ 호스트별 설치

limit-master: ## Masters 그룹만 대상 설치 (--limit masters)
	@echo "==> Master 노드만 설치 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --limit masters

limit-workers: ## Workers 그룹만 대상 설치 (--limit workers)
	@echo "==> Worker 노드만 설치 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --limit workers

limit-master1: ## master1 호스트만 대상 설치 (--limit master1)
	@echo "==> master1만 설치 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --limit master1

##@ Worker 노드 관리

check-workers: ## Worker 상태 확인 (inventory vs 클러스터 비교)
	@echo "==> Worker 노드 상태 확인 중..."
	@echo ""
	@echo "인벤토리 Worker 목록:"
	@ansible workers -i $(INVENTORY) --list-hosts | grep -v "hosts ("
	@echo ""
	@echo "클러스터에 등록된 노드:"
	@ansible masters -i $(INVENTORY) -m shell -a "kubectl get nodes -o custom-columns=NAME:.metadata.name --no-headers" 2>/dev/null | grep -v ">>>" || echo "클러스터 정보를 가져올 수 없습니다"

add-workers: ## Worker 노드 수동 추가 (add-worker.yml)
	@echo "==> Worker 노드 추가 중..."
	ansible-playbook -i $(INVENTORY) $(ADD_WORKER_PLAYBOOK)

check-and-add-workers: ## 미등록 Worker 자동 감지 및 조인
	@echo "==> Worker 상태 확인 및 자동 추가 중..."
	ansible-playbook -i $(INVENTORY) $(CHECK_ADD_WORKERS_PLAYBOOK)

##@ 리셋 및 정리

reset: ## 전체 클러스터 초기화 (kubeadm reset) [확인 필요]
	@echo "==> 전체 클러스터 초기화 중..."
	@read -p "정말로 클러스터를 초기화하시겠습니까? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	ansible-playbook -i $(INVENTORY) $(RESET_PLAYBOOK)

reset-workers: ## Worker 노드만 초기화 (kubeadm reset) [확인 필요]
	@echo "==> Worker 노드 초기화 중..."
	@read -p "정말로 Worker 노드를 초기화하시겠습니까? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	ansible-playbook -i $(INVENTORY) $(RESET_PLAYBOOK) --limit workers

##@ 유틸리티

show-inventory: ## 인벤토리 호스트 트리 구조 표시
	@echo "==> 인벤토리 호스트 목록:"
	@ansible-inventory -i $(INVENTORY) --graph

show-variables: ## 전역 변수 출력 (group_vars/all.yml)
	@echo "==> 전역 변수 (group_vars/all.yml):"
	@cat group_vars/all.yml

lint: ## Playbook YAML 문법 검사 (--syntax-check)
	@echo "==> Playbook 문법 검사 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --syntax-check

list-tags: ## 사용 가능한 Ansible tags 목록 표시
	@echo "==> 사용 가능한 Tags:"
	@ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --list-tags

list-tasks: ## 모든 Ansible tasks 목록 표시
	@echo "==> 모든 Tasks:"
	@ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --list-tasks

##@ 고급 명령어

install-ha: ## HA 클러스터 설치 (master_ha: true 필요)
	@echo "==> HA 클러스터 설치 중..."
	@echo "주의: group_vars/all.yml에서 master_ha: true 설정 확인"
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK)

reinstall-k8s: ## K8s만 재설치 (시스템 준비 완료 가정, k8s+networking)
	@echo "==> Kubernetes 재설치 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags kubernetes,networking

update-registry: ## 레지스트리 설정 업데이트 (credentials + CoreDNS)
	@echo "==> 레지스트리 설정 업데이트 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags docker-credentials,coredns-hosts

dry-run: ## Dry-run 모드 (변경사항 미리보기, --check --diff)
	@echo "==> Dry run 모드 실행 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --check --diff

##@ 개발 명령어

test-connection: ## 호스트 그룹별 ping 테스트 (masters, workers, installs)
	@echo "==> Masters 연결 테스트:"
	ansible masters -i $(INVENTORY) -m ping
	@echo ""
	@echo "==> Workers 연결 테스트:"
	ansible workers -i $(INVENTORY) -m ping
	@echo ""
	@echo "==> Installs 연결 테스트:"
	ansible installs -i $(INVENTORY) -m ping

get-join-command: ## Worker join 명령어 생성 (kubeadm token create)
	@echo "==> Worker join 명령어:"
	ansible masters -i $(INVENTORY) -m shell -a "kubeadm token create --print-join-command" | grep -v ">>>"

check-versions: ## 설치된 버전 확인 (kubectl, containerd)
	@echo "==> 설치된 버전 확인:"
	@echo ""
	@echo "Kubernetes 버전:"
	ansible all -i $(INVENTORY) -m shell -a "kubectl version --client --short 2>/dev/null || echo 'Not installed'" | grep -v ">>>"
	@echo ""
	@echo "Containerd 버전:"
	ansible all -i $(INVENTORY) -m shell -a "containerd --version 2>/dev/null || echo 'Not installed'" | grep -v ">>>"

##@ 커스텀 명령어 실행

cmd-all: ## 모든 호스트 명령 실행 [상세 출력] (예: make cmd-all CMD="uptime")
	@if [ -z "$(CMD)" ]; then \
		echo "에러: CMD 변수가 비어있습니다."; \
		echo "사용법: make cmd-all CMD=\"your-command\""; \
		echo "예시: make cmd-all CMD=\"uptime\""; \
		exit 1; \
	fi
	@echo "==> 모든 호스트에서 명령어 실행: $(CMD)"
	@echo ""
	@ansible all -i $(INVENTORY) -m shell -a "$(CMD)" -v

cmd-masters: ## Masters 그룹 명령 실행 [상세 출력] (예: make cmd-masters CMD="kubectl get nodes")
	@if [ -z "$(CMD)" ]; then \
		echo "에러: CMD 변수가 비어있습니다."; \
		echo "사용법: make cmd-masters CMD=\"your-command\""; \
		echo "예시: make cmd-masters CMD=\"kubectl get nodes\""; \
		exit 1; \
	fi
	@echo "==> Master 노드에서 명령어 실행: $(CMD)"
	@echo ""
	@ansible masters -i $(INVENTORY) -m shell -a "$(CMD)" -v

cmd-workers: ## Workers 그룹 명령 실행 [상세 출력] (예: make cmd-workers CMD="free -h")
	@if [ -z "$(CMD)" ]; then \
		echo "에러: CMD 변수가 비어있습니다."; \
		echo "사용법: make cmd-workers CMD=\"your-command\""; \
		echo "예시: make cmd-workers CMD=\"free -h\""; \
		exit 1; \
	fi
	@echo "==> Worker 노드에서 명령어 실행: $(CMD)"
	@echo ""
	@ansible workers -i $(INVENTORY) -m shell -a "$(CMD)" -v

cmd-installs: ## Installs 그룹 명령 실행 [상세 출력] (예: make cmd-installs CMD="nerdctl ps")
	@if [ -z "$(CMD)" ]; then \
		echo "에러: CMD 변수가 비어있습니다."; \
		echo "사용법: make cmd-installs CMD=\"your-command\""; \
		echo "예시: make cmd-installs CMD=\"nerdctl ps\""; \
		exit 1; \
	fi
	@echo "==> Installs 노드에서 명령어 실행: $(CMD)"
	@echo ""
	@ansible installs -i $(INVENTORY) -m shell -a "$(CMD)" -v

cmd-host: ## 특정 호스트 명령 실행 [상세 출력] (예: make cmd-host HOST="master1" CMD="uptime")
	@if [ -z "$(HOST)" ]; then \
		echo "에러: HOST 변수가 비어있습니다."; \
		echo "사용법: make cmd-host HOST=\"hostname\" CMD=\"your-command\""; \
		echo "예시: make cmd-host HOST=\"master1\" CMD=\"kubectl get nodes\""; \
		echo ""; \
		echo "사용 가능한 호스트 목록:"; \
		ansible-inventory -i $(INVENTORY) --list | grep -oP '(?<=")\w+(?=":)' | sort -u | grep -v "hostvars\|all\|ungrouped\|masters\|workers\|installs" | sed 's/^/  - /'; \
		exit 1; \
	fi
	@if [ -z "$(CMD)" ]; then \
		echo "에러: CMD 변수가 비어있습니다."; \
		echo "사용법: make cmd-host HOST=\"hostname\" CMD=\"your-command\""; \
		echo "예시: make cmd-host HOST=\"master1\" CMD=\"kubectl get nodes\""; \
		exit 1; \
	fi
	@echo "==> $(HOST) 호스트에서 명령어 실행: $(CMD)"
	@echo ""
	@ansible $(HOST) -i $(INVENTORY) -m shell -a "$(CMD)" -v

command: cmd-all ## cmd-all 별칭 (예: make command CMD="df -h")

##@ 로컬 레지스트리 관리

registry-init: ## 레지스트리 설정 초기화 (.env.registry.example → .env.registry)
	@if [ -f .env.registry ]; then \
		echo "==> .env.registry 파일이 이미 존재합니다."; \
		echo "기존 설정을 유지합니다. 재설정하려면 .env.registry를 삭제하세요."; \
	else \
		echo "==> .env.registry 파일 생성 중..."; \
		cp .env.registry.example .env.registry; \
		echo "==> .env.registry 파일이 생성되었습니다."; \
		echo "필요에 따라 .env.registry 파일을 수정하세요."; \
	fi

registry-start: ## 로컬 레지스트리 시작 (nerdctl run, scripts/manage-registry.sh)
	@./scripts/manage-registry.sh start

registry-stop: ## 로컬 레지스트리 중지 (nerdctl stop)
	@./scripts/manage-registry.sh stop

registry-restart: ## 로컬 레지스트리 재시작 (stop → start)
	@./scripts/manage-registry.sh restart

registry-status: ## 로컬 레지스트리 상태 확인 (nerdctl ps)
	@./scripts/manage-registry.sh status

registry-remove: ## 로컬 레지스트리 컨테이너 제거 (nerdctl rm -f)
	@./scripts/manage-registry.sh remove

registry-logs: ## 로컬 레지스트리 로그 확인 (nerdctl logs)
	@./scripts/manage-registry.sh logs

##@ NFS 서버 관리

nfs-init: ## NFS 설정 초기화 (.env.nfs.example → .env.nfs)
	@if [ -f .env.nfs ]; then \
		echo "==> .env.nfs 파일이 이미 존재합니다."; \
		echo "기존 설정을 유지합니다. 재설정하려면 .env.nfs를 삭제하세요."; \
	else \
		echo "==> .env.nfs 파일 생성 중..."; \
		cp .env.nfs.example .env.nfs; \
		echo "==> .env.nfs 파일이 생성되었습니다."; \
		echo "필요에 따라 .env.nfs 파일을 수정하세요."; \
	fi

nfs-install: ## NFS 서버 설치 및 초기 설정 (패키지 + exports + start)
	@./scripts/manage-nfs.sh install

nfs-start: ## NFS 서버 시작 (systemctl start)
	@./scripts/manage-nfs.sh start

nfs-stop: ## NFS 서버 중지 (systemctl stop)
	@./scripts/manage-nfs.sh stop

nfs-restart: ## NFS 서버 재시작 (stop → start)
	@./scripts/manage-nfs.sh restart

nfs-status: ## NFS 서버 상태 확인 (systemctl status + exportfs -v)
	@./scripts/manage-nfs.sh status

nfs-reload: ## NFS exports 재로드 (exportfs -ra)
	@./scripts/manage-nfs.sh reload

nfs-show-exports: ## /etc/exports 설정 표시
	@./scripts/manage-nfs.sh show-exports

nfs-add-export: ## 설정된 exports 추가 및 적용
	@./scripts/manage-nfs.sh add-export

nfs-remove: ## NFS 서버 설정 제거 (exports 백업 후 삭제)
	@./scripts/manage-nfs.sh remove

##@ Ubuntu 로컬 저장소 관리

ubuntu-repo-init: ## Ubuntu repo 설정 초기화 (.env.ubuntu-repo.example → .env.ubuntu-repo)
	@if [ -f .env.ubuntu-repo ]; then \
		echo "==> .env.ubuntu-repo 파일이 이미 존재합니다."; \
		echo "기존 설정을 유지합니다. 재설정하려면 .env.ubuntu-repo를 삭제하세요."; \
	else \
		echo "==> .env.ubuntu-repo 파일 생성 중..."; \
		cp .env.ubuntu-repo.example .env.ubuntu-repo; \
		echo "==> .env.ubuntu-repo 파일이 생성되었습니다."; \
		echo "필요에 따라 .env.ubuntu-repo 파일을 수정하세요."; \
	fi

ubuntu-repo-setup: ## Ubuntu 로컬 APT 저장소 설정 (mv + chown + apt config) [root 필요]
	@sudo ./scripts/manage-ubuntu-repo.sh setup

ubuntu-repo-remove: ## Ubuntu 로컬 저장소 APT 설정 제거
	@sudo ./scripts/manage-ubuntu-repo.sh remove

ubuntu-repo-status: ## Ubuntu 로컬 저장소 상태 확인 (디렉토리 + APT 설정)
	@./scripts/manage-ubuntu-repo.sh status

ubuntu-repo-update-sources: ## APT sources.list만 업데이트 [root 필요]
	@sudo ./scripts/manage-ubuntu-repo.sh update-sources

##@ Apache HTTP 저장소 서버

apache-repo-install: ## Apache 설치 및 HTTP 저장소 설정 [root 필요]
	@sudo ./scripts/manage-ubuntu-repo.sh apache-install

apache-repo-start: ## Apache 서비스 시작 [root 필요]
	@sudo ./scripts/manage-ubuntu-repo.sh apache-start

apache-repo-stop: ## Apache 서비스 중지 [root 필요]
	@sudo ./scripts/manage-ubuntu-repo.sh apache-stop

apache-repo-restart: ## Apache 서비스 재시작 [root 필요]
	@sudo ./scripts/manage-ubuntu-repo.sh apache-restart

apache-repo-status: ## Apache 서비스 상태 확인
	@./scripts/manage-ubuntu-repo.sh apache-status

apache-repo-remove: ## Apache 저장소 설정 제거 [root 필요]
	@sudo ./scripts/manage-ubuntu-repo.sh apache-remove
