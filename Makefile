.PHONY: help install install-step1 install-step2 install-step3 install-all
.PHONY: reset ping check-cluster
.PHONY: tag-sysctl tag-packages tag-container tag-kubernetes tag-networking
.PHONY: tag-certs tag-coredns tag-harbor tag-docker-credentials
.PHONY: limit-master limit-workers
.PHONY: command cmd-all cmd-masters cmd-workers cmd-installs
.PHONY: check-workers add-workers check-and-add-workers

.DEFAULT_GOAL := help

# 변수 설정
INVENTORY := inventory.ini
PLAYBOOK := site.yml
RESET_PLAYBOOK := reset_cluster.yml
ADD_WORKER_PLAYBOOK := add-worker.yml
CHECK_ADD_WORKERS_PLAYBOOK := check-and-add-workers.yml

##@ 일반 명령어

help: ## 사용 가능한 Make 명령어 목록 표시
	@awk 'BEGIN {FS = ":.*##"; printf "\n\033[1m사용법:\033[0m\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

ping: ## 모든 호스트에 연결 테스트
	@echo "==> 모든 호스트 연결 테스트 중..."
	ansible all -i $(INVENTORY) -m ping

check-cluster: ## 클러스터 상태 확인
	@echo "==> 클러스터 상태 확인 중..."
	ansible masters -i $(INVENTORY) -m shell -a "kubectl get nodes -o wide"
	@echo ""
	@echo "==> 시스템 Pod 상태:"
	ansible masters -i $(INVENTORY) -m shell -a "kubectl get pods -A"

##@ 설치 명령어

install: ## 전체 Kubernetes 클러스터 설치
	@echo "==> 전체 Kubernetes 클러스터 설치 시작..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK)

install-step1: ## Phase 1: 시스템 준비 (sysctl, packages, container)
	@echo "==> Phase 1: 시스템 준비 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags sysctl,packages,container

install-step2: ## Phase 2: Kubernetes 설치
	@echo "==> Phase 2: Kubernetes 설치 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags kubernetes

install-step3: ## Phase 3: 네트워크 플러그인 설치
	@echo "==> Phase 3: 네트워크 플러그인 설치 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags networking

install-all: install-step1 install-step2 install-step3 ## 단계별 전체 설치 (step1 -> step2 -> step3)
	@echo "==> 모든 설치 단계 완료!"

install-minimal: ## 최소 구성 설치 (시스템 + 컨테이너 + Kubernetes + 네트워크)
	@echo "==> 최소 구성 설치 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags sysctl,container,kubernetes,networking

install-production: ## 프로덕션 전체 설치 (모든 기능 포함)
	@echo "==> 프로덕션 전체 설치 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags sysctl,packages,container,docker-credentials,kubernetes,networking,k8s-certs,coredns-hosts

##@ Tag 기반 설치

tag-sysctl: ## Sysctl 및 커널 파라미터 설정
	@echo "==> Sysctl 설정 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags sysctl

tag-packages: ## OS 패키지 설치
	@echo "==> OS 패키지 설치 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags packages

tag-container: ## 컨테이너 런타임 (containerd) 설치
	@echo "==> 컨테이너 런타임 설치 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags container

tag-docker-credentials: ## 레지스트리 인증 설정
	@echo "==> 레지스트리 인증 설정 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags docker-credentials

tag-kubernetes: ## Kubernetes 설치
	@echo "==> Kubernetes 설치 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags kubernetes

tag-networking: ## CNI 플러그인 (Flannel) 설치
	@echo "==> 네트워크 플러그인 설치 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags networking

tag-certs: ## Kubernetes 인증서 10년 연장
	@echo "==> 인증서 연장 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags k8s-certs

tag-coredns: ## CoreDNS 호스트 설정
	@echo "==> CoreDNS 설정 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags coredns-hosts

tag-harbor: ## Harbor 프로젝트 설정
	@echo "==> Harbor 프로젝트 설정 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags harbor-setup

tag-scheduling: ## Master 노드 스케줄링 허용
	@echo "==> Master 노드 스케줄링 설정 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags scheduling

tag-local-registry: ## 로컬 Docker 레지스트리 배포
	@echo "==> 로컬 레지스트리 배포 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags local-registry

##@ 호스트별 설치

limit-master: ## Master 노드만 설치
	@echo "==> Master 노드만 설치 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --limit masters

limit-workers: ## Worker 노드만 설치
	@echo "==> Worker 노드만 설치 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --limit workers

limit-master1: ## master1만 설치
	@echo "==> master1만 설치 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --limit master1

##@ Worker 노드 관리

check-workers: ## Worker 노드 상태 확인 (클러스터에 조인되었는지 체크)
	@echo "==> Worker 노드 상태 확인 중..."
	@echo ""
	@echo "인벤토리 Worker 목록:"
	@ansible workers -i $(INVENTORY) --list-hosts | grep -v "hosts ("
	@echo ""
	@echo "클러스터에 등록된 노드:"
	@ansible masters -i $(INVENTORY) -m shell -a "kubectl get nodes -o custom-columns=NAME:.metadata.name --no-headers" 2>/dev/null | grep -v ">>>" || echo "클러스터 정보를 가져올 수 없습니다"

add-workers: ## 새 Worker 노드 추가 (기존 add-worker.yml 사용)
	@echo "==> Worker 노드 추가 중..."
	ansible-playbook -i $(INVENTORY) $(ADD_WORKER_PLAYBOOK)

check-and-add-workers: ## Worker 상태 확인 후 자동으로 미등록 노드 추가
	@echo "==> Worker 상태 확인 및 자동 추가 중..."
	ansible-playbook -i $(INVENTORY) $(CHECK_ADD_WORKERS_PLAYBOOK)

##@ 리셋 및 정리

reset: ## 전체 클러스터 초기화
	@echo "==> 전체 클러스터 초기화 중..."
	@read -p "정말로 클러스터를 초기화하시겠습니까? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	ansible-playbook -i $(INVENTORY) $(RESET_PLAYBOOK)

reset-workers: ## Worker 노드만 초기화
	@echo "==> Worker 노드 초기화 중..."
	@read -p "정말로 Worker 노드를 초기화하시겠습니까? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	ansible-playbook -i $(INVENTORY) $(RESET_PLAYBOOK) --limit workers

##@ 유틸리티

show-inventory: ## 인벤토리 호스트 목록 표시
	@echo "==> 인벤토리 호스트 목록:"
	@ansible-inventory -i $(INVENTORY) --graph

show-variables: ## 전역 변수 확인
	@echo "==> 전역 변수 (group_vars/all.yml):"
	@cat group_vars/all.yml

lint: ## Ansible playbook 문법 체크
	@echo "==> Playbook 문법 검사 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --syntax-check

list-tags: ## 사용 가능한 모든 tags 목록 표시
	@echo "==> 사용 가능한 Tags:"
	@ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --list-tags

list-tasks: ## 모든 tasks 목록 표시
	@echo "==> 모든 Tasks:"
	@ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --list-tasks

##@ 고급 명령어

install-ha: ## 고가용성(HA) 클러스터 설치
	@echo "==> HA 클러스터 설치 중..."
	@echo "주의: group_vars/all.yml에서 master_ha: true 설정 확인"
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK)

reinstall-k8s: ## Kubernetes만 재설치 (시스템 준비 완료 가정)
	@echo "==> Kubernetes 재설치 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags kubernetes,networking

update-registry: ## 레지스트리 설정 업데이트
	@echo "==> 레지스트리 설정 업데이트 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --tags docker-credentials,coredns-hosts

dry-run: ## Dry run 모드로 실행 (변경사항 미적용)
	@echo "==> Dry run 모드 실행 중..."
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --check --diff

##@ 개발 명령어

test-connection: ## 각 호스트 그룹별 연결 테스트
	@echo "==> Masters 연결 테스트:"
	ansible masters -i $(INVENTORY) -m ping
	@echo ""
	@echo "==> Workers 연결 테스트:"
	ansible workers -i $(INVENTORY) -m ping
	@echo ""
	@echo "==> Installs 연결 테스트:"
	ansible installs -i $(INVENTORY) -m ping

get-join-command: ## Worker join 명령어 가져오기
	@echo "==> Worker join 명령어:"
	ansible masters -i $(INVENTORY) -m shell -a "kubeadm token create --print-join-command" | grep -v ">>>"

check-versions: ## 설치된 버전 확인
	@echo "==> 설치된 버전 확인:"
	@echo ""
	@echo "Kubernetes 버전:"
	ansible all -i $(INVENTORY) -m shell -a "kubectl version --client --short 2>/dev/null || echo 'Not installed'" | grep -v ">>>"
	@echo ""
	@echo "Containerd 버전:"
	ansible all -i $(INVENTORY) -m shell -a "containerd --version 2>/dev/null || echo 'Not installed'" | grep -v ">>>"

##@ 커스텀 명령어 실행

cmd-all: ## 모든 호스트에 명령어 실행 (사용법: make cmd-all CMD="ls -la")
	@if [ -z "$(CMD)" ]; then \
		echo "에러: CMD 변수가 비어있습니다."; \
		echo "사용법: make cmd-all CMD=\"your-command\""; \
		echo "예시: make cmd-all CMD=\"uptime\""; \
		exit 1; \
	fi
	@echo "==> 모든 호스트에서 명령어 실행: $(CMD)"
	ansible all -i $(INVENTORY) -m shell -a "$(CMD)"

cmd-masters: ## Master 노드에만 명령어 실행 (사용법: make cmd-masters CMD="kubectl get nodes")
	@if [ -z "$(CMD)" ]; then \
		echo "에러: CMD 변수가 비어있습니다."; \
		echo "사용법: make cmd-masters CMD=\"your-command\""; \
		echo "예시: make cmd-masters CMD=\"kubectl get nodes\""; \
		exit 1; \
	fi
	@echo "==> Master 노드에서 명령어 실행: $(CMD)"
	ansible masters -i $(INVENTORY) -m shell -a "$(CMD)"

cmd-workers: ## Worker 노드에만 명령어 실행 (사용법: make cmd-workers CMD="docker ps")
	@if [ -z "$(CMD)" ]; then \
		echo "에러: CMD 변수가 비어있습니다."; \
		echo "사용법: make cmd-workers CMD=\"your-command\""; \
		echo "예시: make cmd-workers CMD=\"free -h\""; \
		exit 1; \
	fi
	@echo "==> Worker 노드에서 명령어 실행: $(CMD)"
	ansible workers -i $(INVENTORY) -m shell -a "$(CMD)"

cmd-installs: ## Installs 노드에만 명령어 실행 (사용법: make cmd-installs CMD="df -h")
	@if [ -z "$(CMD)" ]; then \
		echo "에러: CMD 변수가 비어있습니다."; \
		echo "사용법: make cmd-installs CMD=\"your-command\""; \
		echo "예시: make cmd-installs CMD=\"nerdctl ps\""; \
		exit 1; \
	fi
	@echo "==> Installs 노드에서 명령어 실행: $(CMD)"
	ansible installs -i $(INVENTORY) -m shell -a "$(CMD)"

command: cmd-all ## cmd-all의 별칭 (사용법: make command CMD="your-command")
