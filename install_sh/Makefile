# Makefile for Kubernetes Cluster Setup
# Usage: make <target>
# Example: make all  or  make repo  or  make install-k8s

.PHONY: all help check-root detect-os repo packages system sysctl containerd chrony kubernetes kubectl-setup summary clean

# Load environment variables from .env file if it exists
ifneq (,$(wildcard .env))
    include .env
    export
endif

# Configuration (can be overridden by .env file)
KUBERNETES_VERSION ?= 1.27.14
CONTAINERD_VERSION ?= 1.7.6
POD_SUBNET ?= 10.244.0.0/16
SERVICE_SUBNET ?= 10.96.0.0/12
TIMEZONE ?= Asia/Seoul

# Repository settings - RHEL/CentOS
USE_LOCAL_REPO ?= true
USE_ISO_REPO ?= true
ISO_MOUNT_POINT ?= /mnt/cdrom
ISO_FILE_PATH ?= /root/rhel-9.4-x86_64-dvd.iso
YUM_REPO_DIR ?= /root/yum-repo
REPO_WEB_PORT ?= 8080

# Repository settings - Ubuntu
USE_LOCAL_APT_REPO ?= true
APT_REPO_URL ?= http://192.168.135.1:8080/ubuntu
APT_REPO_MIRROR ?= http://kr.archive.ubuntu.com/ubuntu
APT_REPO_DISTRIBUTION ?= jammy
APT_COMPONENTS ?= main restricted universe multiverse

# Registry settings
INSECURE_REGISTRIES ?= cr.makina.rocks harbor.runway.test

# Colors
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m

# Log functions
define log_info
	@echo -e "$(GREEN)[INFO]$(NC) $(1)"
endef

define log_warn
	@echo -e "$(YELLOW)[WARN]$(NC) $(1)"
endef

define log_error
	@echo -e "$(RED)[ERROR]$(NC) $(1)"
endef

define log_step
	@echo ""
	@echo -e "$(BLUE)========================================$(NC)"
	@echo -e "$(BLUE)$(1)$(NC)"
	@echo -e "$(BLUE)========================================$(NC)"
endef

# Default target
all: check-root detect-os repo packages system sysctl containerd chrony kubernetes kubectl-setup summary

# Help target
help:
	@echo "Kubernetes Cluster Setup - Makefile targets:"
	@echo ""
	@echo "  make all              - Run full installation (all steps)"
	@echo "  make check-root       - Check if running as root"
	@echo "  make detect-os        - Detect operating system"
	@echo "  make repo             - Configure package repository"
	@echo "  make packages         - Install required packages"
	@echo "  make system           - Configure system settings"
	@echo "  make sysctl           - Configure kernel parameters"
	@echo "  make containerd       - Install and configure containerd"
	@echo "  make chrony           - Configure time synchronization"
	@echo "  make kubernetes       - Install Kubernetes packages"
	@echo "  make kubectl-setup    - Setup kubectl completion and aliases"
	@echo "  make summary          - Display installation summary"
	@echo "  make clean            - Clean up temporary files"
	@echo ""
	@echo "  make minimal          - Install only essential components (repo + packages + kubernetes)"
	@echo "  make system-only      - Configure system settings only (system + sysctl)"
	@echo "  make runtime          - Install container runtime only (containerd)"
	@echo ""
	@echo ""
	@echo "Configuration:"
	@echo "  Create .env file from .env.example to customize settings"
	@echo "  cp .env.example .env"
	@echo ""
	@echo "  Or edit Makefile variables directly:"
	@echo "  RHEL/CentOS:"
	@echo "    USE_LOCAL_REPO       - Use local YUM repository"
	@echo "    USE_ISO_REPO         - Use ISO mounted repository"
	@echo "    ISO_FILE_PATH        - Path to RHEL/CentOS ISO"
	@echo "    YUM_REPO_DIR         - Local YUM repository directory"
	@echo ""
	@echo "  Ubuntu:"
	@echo "    USE_LOCAL_APT_REPO   - Use local APT repository"
	@echo "    APT_REPO_URL         - Local APT repository URL"
	@echo "    APT_REPO_MIRROR      - Ubuntu mirror URL"
	@echo "    APT_REPO_DISTRIBUTION - Ubuntu distribution (jammy, focal, etc)"
	@echo ""

# Check if running as root
check-root:
	$(call log_step,Checking Root Privileges)
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo -e "\033[0;31m[ERROR]\033[0m This must be run as root"; \
		exit 1; \
	fi
	$(call log_info,Running as root ✓)

# Detect OS
detect-os:
	$(call log_step,Detecting Operating System)
	@if [ -f /etc/os-release ]; then \
		. /etc/os-release; \
		echo "$$ID" > /tmp/.k8s-os; \
		echo "$$VERSION_ID" > /tmp/.k8s-os-version; \
		echo -e "\033[0;32m[INFO]\033[0m OS: $$ID $$VERSION_ID"; \
	else \
		echo -e "\033[0;31m[ERROR]\033[0m Cannot detect OS"; \
		exit 1; \
	fi
	@MASTER_IP=$$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1); \
	echo "$$MASTER_IP" > /tmp/.k8s-master-ip; \
	echo -e "\033[0;32m[INFO]\033[0m Local IP: $$MASTER_IP"

# Configure repository
repo: check-root detect-os
	$(call log_step,Step 1: Configuring Repository)
	@OS=$$(cat /tmp/.k8s-os); \
	if [ "$$OS" = "rhel" ] || [ "$$OS" = "centos" ] || [ "$$OS" = "rocky" ]; then \
		$(MAKE) -s repo-rhel; \
	elif [ "$$OS" = "ubuntu" ]; then \
		$(MAKE) -s repo-ubuntu; \
	fi

repo-rhel:
	$(call log_info,Configuring RHEL/CentOS repository)
	@rm -f /etc/yum.repos.d/*.repo
	@if [ "$(USE_ISO_REPO)" = "true" ]; then \
		if ! mountpoint -q "$(ISO_MOUNT_POINT)"; then \
			echo -e "\033[0;32m[INFO]\033[0m Mounting ISO..."; \
			mkdir -p "$(ISO_MOUNT_POINT)"; \
			mount -o loop,ro "$(ISO_FILE_PATH)" "$(ISO_MOUNT_POINT)" || echo -e "\033[1;33m[WARN]\033[0m Failed to mount ISO"; \
		fi; \
	fi
	@if [ "$(USE_ISO_REPO)" = "true" ]; then \
		echo "[local-iso-baseos]" > /etc/yum.repos.d/local-iso.repo; \
		echo "name=Local ISO BaseOS Repository" >> /etc/yum.repos.d/local-iso.repo; \
		echo "baseurl=file://$(ISO_MOUNT_POINT)/BaseOS" >> /etc/yum.repos.d/local-iso.repo; \
		echo "enabled=1" >> /etc/yum.repos.d/local-iso.repo; \
		echo "gpgcheck=0" >> /etc/yum.repos.d/local-iso.repo; \
		echo "priority=1" >> /etc/yum.repos.d/local-iso.repo; \
		echo "" >> /etc/yum.repos.d/local-iso.repo; \
		echo "[local-iso-appstream]" >> /etc/yum.repos.d/local-iso.repo; \
		echo "name=Local ISO AppStream Repository" >> /etc/yum.repos.d/local-iso.repo; \
		echo "baseurl=file://$(ISO_MOUNT_POINT)/AppStream" >> /etc/yum.repos.d/local-iso.repo; \
		echo "enabled=1" >> /etc/yum.repos.d/local-iso.repo; \
		echo "gpgcheck=0" >> /etc/yum.repos.d/local-iso.repo; \
		echo "priority=1" >> /etc/yum.repos.d/local-iso.repo; \
	fi
	@if [ "$(USE_ISO_REPO)" = "true" ]; then \
		echo -e "\033[0;32m[INFO]\033[0m ISO repository configured"; \
	fi
	@if [ "$(USE_LOCAL_REPO)" = "true" ] && [ -d "$(YUM_REPO_DIR)" ]; then \
		echo "[local-yum-repo]" > /etc/yum.repos.d/local-yum.repo; \
		echo "name=Local YUM Repository" >> /etc/yum.repos.d/local-yum.repo; \
		echo "baseurl=file://$(YUM_REPO_DIR)" >> /etc/yum.repos.d/local-yum.repo; \
		echo "enabled=1" >> /etc/yum.repos.d/local-yum.repo; \
		echo "gpgcheck=0" >> /etc/yum.repos.d/local-yum.repo; \
		echo "priority=1" >> /etc/yum.repos.d/local-yum.repo; \
	fi
	@if [ "$(USE_LOCAL_REPO)" = "true" ] && [ -d "$(YUM_REPO_DIR)" ]; then \
		echo -e "\033[0;32m[INFO]\033[0m Local YUM repository configured"; \
	fi
	@yum clean all > /dev/null 2>&1
	$(call log_info,Repository configuration complete)

repo-ubuntu:
	$(call log_info,Configuring Ubuntu repository)
	@# Backup original sources.list
	@if [ -f /etc/apt/sources.list ] && [ ! -f /etc/apt/sources.list.backup ]; then \
		cp /etc/apt/sources.list /etc/apt/sources.list.backup; \
		echo -e "\033[0;32m[INFO]\033[0m Backed up original sources.list"; \
	fi
	@if [ "$(USE_LOCAL_APT_REPO)" = "true" ]; then \
		echo -e "\033[0;32m[INFO]\033[0m Configuring local APT repository..."; \
	else \
		echo -e "\033[0;32m[INFO]\033[0m Configuring mirror APT repository..."; \
	fi
	@if [ "$(USE_LOCAL_APT_REPO)" = "true" ]; then \
		echo "deb [trusted=yes] $(APT_REPO_URL) ./" | tee /etc/apt/sources.list > /dev/null; \
	else \
		echo "# Ubuntu Mirror Repository" > /etc/apt/sources.list; \
		echo "deb $(APT_REPO_MIRROR) $(APT_REPO_DISTRIBUTION) $(APT_COMPONENTS)" >> /etc/apt/sources.list; \
		echo "deb $(APT_REPO_MIRROR) $(APT_REPO_DISTRIBUTION)-updates $(APT_COMPONENTS)" >> /etc/apt/sources.list; \
		echo "deb $(APT_REPO_MIRROR) $(APT_REPO_DISTRIBUTION)-backports $(APT_COMPONENTS)" >> /etc/apt/sources.list; \
		echo "deb $(APT_REPO_MIRROR) $(APT_REPO_DISTRIBUTION)-security $(APT_COMPONENTS)" >> /etc/apt/sources.list; \
	fi
	@if [ "$(USE_LOCAL_APT_REPO)" = "true" ]; then \
		echo -e "\033[0;32m[INFO]\033[0m Local APT repository configured"; \
	else \
		echo -e "\033[0;32m[INFO]\033[0m Mirror APT repository configured"; \
	fi
	@apt-get update > /dev/null 2>&1
	$(call log_info,Repository configuration complete)

# Install required packages
packages: check-root detect-os
	$(call log_step,Step 2: Installing Required Packages)
	@OS=$$(cat /tmp/.k8s-os); \
	if [ "$$OS" = "rhel" ] || [ "$$OS" = "centos" ] || [ "$$OS" = "rocky" ]; then \
		$(MAKE) -s packages-rhel; \
	elif [ "$$OS" = "ubuntu" ]; then \
		$(MAKE) -s packages-ubuntu; \
	fi

packages-rhel:
	$(call log_info,Installing packages via yum/dnf...)
	@yum install -y \
		curl wget vim net-tools bash-completion yum-utils \
		device-mapper-persistent-data lvm2 chrony \
		socat conntrack tar bzip2 \
		> /dev/null 2>&1 || echo -e "\033[1;33m[WARN]\033[0m Some packages failed to install"
	$(call log_info,Package installation complete)

packages-ubuntu:
	$(call log_info,Installing packages via apt...)
	@apt-get install -y \
		apt-transport-https ca-certificates curl \
		software-properties-common gnupg lsb-release chrony \
		socat conntrack \
		> /dev/null 2>&1 || echo -e "\033[1;33m[WARN]\033[0m Some packages failed to install"
	$(call log_info,Package installation complete)

# Configure system settings
system: check-root detect-os
	$(call log_step,Step 3: Configuring System Settings)
	@OS=$$(cat /tmp/.k8s-os); \
	if [ "$$OS" = "rhel" ] || [ "$$OS" = "centos" ] || [ "$$OS" = "rocky" ]; then \
		echo -e "\033[0;32m[INFO]\033[0m Disabling SELinux..."; \
		setenforce 0 2>/dev/null || true; \
		sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config; \
	fi
	$(call log_info,Stopping firewall...)
	@systemctl stop firewalld 2>/dev/null || true
	@systemctl disable firewalld 2>/dev/null || true
	@systemctl stop ufw 2>/dev/null || true
	@systemctl disable ufw 2>/dev/null || true
	$(call log_info,Disabling swap...)
	@swapoff -a
	@sed -i '/swap/d' /etc/fstab
	$(call log_info,Setting timezone to $(TIMEZONE)...)
	@timedatectl set-timezone "$(TIMEZONE)"
	$(call log_info,Configuring /etc/hosts...)
	@MASTER_IP=$$(cat /tmp/.k8s-master-ip); \
	HOSTNAME=$$(hostname); \
	if ! grep -q "$$HOSTNAME" /etc/hosts; then \
		echo "$$MASTER_IP $$HOSTNAME" >> /etc/hosts; \
	fi
	$(call log_info,System configuration complete)

# Configure sysctl parameters
sysctl: check-root
	$(call log_step,Step 4: Configuring Kernel Parameters)
	$(call log_info,Setting sysctl parameters for Kubernetes...)
	@{ \
		echo "# Enable IP forwarding"; \
		echo "net.ipv4.ip_forward = 1"; \
		echo "net.ipv6.conf.all.forwarding = 1"; \
		echo ""; \
		echo "# Bridge network"; \
		echo "net.bridge.bridge-nf-call-iptables = 1"; \
		echo "net.bridge.bridge-nf-call-ip6tables = 1"; \
		echo ""; \
		echo "# File descriptors"; \
		echo "fs.file-max = 2097152"; \
		echo "fs.inotify.max_user_instances = 8192"; \
		echo "fs.inotify.max_user_watches = 524288"; \
		echo ""; \
		echo "# ARP cache"; \
		echo "net.ipv4.neigh.default.gc_thresh1 = 1024"; \
		echo "net.ipv4.neigh.default.gc_thresh2 = 4096"; \
		echo "net.ipv4.neigh.default.gc_thresh3 = 8192"; \
	} > /etc/sysctl.d/99-kubernetes.conf
	@modprobe br_netfilter 2>/dev/null || true
	@modprobe overlay 2>/dev/null || true
	@{ \
		echo "br_netfilter"; \
		echo "overlay"; \
	} > /etc/modules-load.d/k8s.conf
	@sysctl -p /etc/sysctl.d/99-kubernetes.conf > /dev/null 2>&1 || true
	$(call log_info,Kernel parameters configured)

# Install and configure Containerd
containerd: check-root detect-os
	$(call log_step,Step 5: Installing Containerd)
	@OS=$$(cat /tmp/.k8s-os); \
	if [ "$$OS" = "rhel" ] || [ "$$OS" = "centos" ] || [ "$$OS" = "rocky" ]; then \
		echo -e "\033[0;32m[INFO]\033[0m Installing containerd via yum..."; \
		yum install -y containerd.io 2>/dev/null || yum install -y containerd 2>/dev/null; \
	elif [ "$$OS" = "ubuntu" ]; then \
		echo -e "\033[0;32m[INFO]\033[0m Installing containerd via apt..."; \
		apt-get install -y containerd.io 2>/dev/null || apt-get install -y containerd 2>/dev/null; \
	fi
	$(call log_info,Configuring containerd...)
	@mkdir -p /etc/containerd
	@containerd config default > /etc/containerd/config.toml
	@sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
	@systemctl daemon-reload
	@systemctl enable containerd
	@systemctl restart containerd
	$(call log_info,Containerd installation complete)

# Configure Chrony (NTP)
chrony: check-root detect-os
	$(call log_step,Step 6: Configuring Time Synchronization)
	$(call log_info,Configuring chrony...)
	@OS=$$(cat /tmp/.k8s-os); \
	if [ "$$OS" = "rhel" ] || [ "$$OS" = "centos" ] || [ "$$OS" = "rocky" ]; then \
		systemctl enable chronyd 2>/dev/null; \
		systemctl start chronyd 2>/dev/null; \
	elif [ "$$OS" = "ubuntu" ]; then \
		systemctl enable chrony 2>/dev/null; \
		systemctl start chrony 2>/dev/null; \
	fi
	@chronyc tracking 2>/dev/null || timedatectl status
	$(call log_info,Time synchronization configured)

# Install Kubernetes packages
kubernetes: check-root detect-os
	$(call log_step,Step 7: Installing Kubernetes Packages)
	@OS=$$(cat /tmp/.k8s-os); \
	if [ "$$OS" = "rhel" ] || [ "$$OS" = "centos" ] || [ "$$OS" = "rocky" ]; then \
		$(MAKE) -s kubernetes-rhel; \
	elif [ "$$OS" = "ubuntu" ]; then \
		$(MAKE) -s kubernetes-ubuntu; \
	fi

kubernetes-rhel:
	$(call log_info,Installing Kubernetes packages for RHEL/CentOS...)
	@cat > /etc/yum.repos.d/kubernetes.repo <<-'EOF'
	[kubernetes]
	name=Kubernetes
	baseurl=https://pkgs.k8s.io/core:/stable:/v1.27/rpm/
	enabled=1
	gpgcheck=1
	gpgkey=https://pkgs.k8s.io/core:/stable:/v1.27/rpm/repodata/repomd.xml.key
	exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
	EOF
	@K8S_VERSION="$(KUBERNETES_VERSION)-0"; \
	yum install -y \
		kubelet-$$K8S_VERSION \
		kubeadm-$$K8S_VERSION \
		kubectl-$$K8S_VERSION \
		--disableexcludes=kubernetes 2>/dev/null || echo -e "\033[1;33m[WARN]\033[0m Failed to install specific K8s version"
	@systemctl enable kubelet
	$(call log_info,Kubernetes packages installed)

kubernetes-ubuntu:
	$(call log_info,Installing Kubernetes packages for Ubuntu...)
	@mkdir -p /etc/apt/keyrings
	@curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.27/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
	@echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.27/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
	@apt-get update > /dev/null 2>&1
	@K8S_VERSION="$(KUBERNETES_VERSION)-*"; \
	apt-get install -y \
		kubelet=$$K8S_VERSION \
		kubeadm=$$K8S_VERSION \
		kubectl=$$K8S_VERSION \
		2>/dev/null
	@apt-mark hold kubelet kubeadm kubectl
	$(call log_info,Kubernetes packages installed)

# Setup kubectl bash completion and environment
kubectl-setup: check-root
	$(call log_step,Step 8: Setting up kubectl completion and environment)
	@if ! grep -q "# Kubernetes environment PATH" ~/.bashrc; then \
		echo -e "\033[0;32m[INFO]\033[0m Configuring comprehensive PATH..."; \
		cat >> ~/.bashrc <<-'EOF'; \
		; \
		# Kubernetes environment PATH; \
		export PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin:/root/bin:$$PATH"; \
		EOF; \
	fi
	@kubectl completion bash > /etc/bash_completion.d/kubectl 2>/dev/null || true
	@if ! grep -q "alias k=kubectl" ~/.bashrc; then \
		echo -e "\033[0;32m[INFO]\033[0m Adding kubectl aliases..."; \
		cat >> ~/.bashrc <<-'EOF'; \
		; \
		# Kubernetes aliases; \
		alias k=kubectl; \
		alias kgp='kubectl get pods'; \
		alias kgs='kubectl get svc'; \
		alias kgn='kubectl get nodes'; \
		alias kga='kubectl get all'; \
		alias kgpa='kubectl get pods -A'; \
		complete -F __start_kubectl k; \
		EOF; \
	fi
	$(call log_info,kubectl completion and environment configured)
	$(call log_info,Run 'source ~/.bashrc' to apply changes to current session)

# Display summary
summary: detect-os
	$(call log_step,Installation Summary)
	@echo ""
	@echo -e "$(GREEN)✓ System prepared for Kubernetes installation$(NC)"
	@echo ""
	@OS=$$(cat /tmp/.k8s-os); \
	OS_VERSION=$$(cat /tmp/.k8s-os-version); \
	MASTER_IP=$$(cat /tmp/.k8s-master-ip); \
	echo -e "$(BLUE)System Information:$(NC)"; \
	echo "  OS: $$OS $$OS_VERSION"; \
	echo "  Hostname: $$(hostname)"; \
	echo "  IP Address: $$MASTER_IP"
	@echo ""
	@echo -e "$(BLUE)Installed Versions:$(NC)"
	@echo "  Containerd: $$(containerd --version 2>/dev/null | awk '{print $$3}' || echo 'N/A')"
	@echo "  Kubeadm: $$(kubeadm version -o short 2>/dev/null || echo 'N/A')"
	@echo "  Kubelet: $$(kubelet --version 2>/dev/null | awk '{print $$2}' || echo 'N/A')"
	@echo "  Kubectl: $$(kubectl version --client -o yaml 2>/dev/null | grep gitVersion | awk '{print $$2}' || echo 'N/A')"
	@echo ""
	@echo -e "$(YELLOW)Next Steps:$(NC)"
	@echo "  1. Initialize master node:"
	@echo "     $(GREEN)kubeadm init --pod-network-cidr=$(POD_SUBNET) --service-cidr=$(SERVICE_SUBNET)$(NC)"
	@echo ""
	@echo "  2. Configure kubectl for your user:"
	@echo "     $(GREEN)mkdir -p \$$HOME/.kube$(NC)"
	@echo "     $(GREEN)cp /etc/kubernetes/admin.conf \$$HOME/.kube/config$(NC)"
	@echo "     $(GREEN)chown \$$(id -u):\$$(id -g) \$$HOME/.kube/config$(NC)"
	@echo ""
	@echo "  3. Install network plugin (e.g., Flannel):"
	@echo "     $(GREEN)kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml$(NC)"
	@echo ""

# Clean up temporary files
clean:
	$(call log_info,Cleaning up temporary files...)
	@rm -f /tmp/.k8s-os /tmp/.k8s-os-version /tmp/.k8s-master-ip
	$(call log_info,Cleanup complete)

# Convenience targets
minimal: repo packages kubernetes
	$(call log_info,Minimal installation complete)

system-only: system sysctl
	$(call log_info,System configuration complete)

runtime: containerd
	$(call log_info,Container runtime installation complete)
