# Ansible 설치 가이드 작성

### 기본 정보

---

- OS: ubuntu20.04.06 LTS
- DISK: 300G이상
- NODE:  MASTER  1식 WORKER 2식 + α
- k8s_Version: 1.23.17

### 설치 패키지 정보

---

- ansible_install.sh :  ansible을 설치하기 위한 쉘 스크립트
- create_harbor_user.sh :  harbor 계정 생성 및 PW 생성
- makina_runway_helm.tar.gz :  runway 구성을 위한 helm chart
- makina-runway.tar.gz  : runway 구성을 위한  container_image
- external-hub.tar.gz :  k8s add on 구성을 위한  container_image
- kubernetes-kubeadm.tar.gz : runway 설치를 위한 ansible 파일
- docker.tar.gz : docker registry container_image 입력
- ubuntu_20.04_repo.tar.gz:  OS 설치 파일

### 설치 사전 준비

---

- 먼저 기본 적인 세팅은 되어 있는 상태
    - IP 설정
    - root password 설정
    - 위에 설치된 설치 패키지 정보는 `/root` 디렉토리에 옮겨져 있는 상태
    

### 설치 진행

---

- 먼저 `shell script` 실행을 위해  권한 변경 및 실행을 진행
    
    ```jsx
    $ chmod +x /root/ansible_install.sh
    $ ./ansible_install.sh
    ```
    

- ansible파일 풀기
    
    ```jsx
    $ tar -xvf kubernetes-kubeadm.tar.gz  
    $ cd kubernetes-kubeadm
    ```
    

- ansible 파일 list 확인

```jsx
drwxr-xr-x  2 root root 4096 May 21 07:57 group_vars
-rw-r--r--  1 root root  259 May 22 00:47 inventory.ini
-rw-r--r--  1 root root  997 May 21 07:57 README.md
drwxr-xr-x 36 root root 4096 May 21 07:57 roles
-rw-r--r--  1 root root 1378 May 22 07:16 site.yml
```

- ansible 파일 변수 변경 진행
    - group_vars/all.yml
    - inventory.ini
    - ( 변수 )만 변경 진행 해주면 default 설치는 가능하다
- group_vars/all.yml

```jsx
#! group_vars/all.yml
# how to set domain
main_domain: onboarding1.com # (변수) 사용할 도메인에 주소 입력 필요

# docker-registry setting - to install k8s or runway in offline
docker_registry_ip: "192.168.135.21" # (변수) docker registry로 사용할 IP 작성 필요 ex) master 1번의 IP
registry_port: 5000
registry_version: "2"
registry_data_dir: "/opt/docker-registry"
registry_name: "registry"
load_image: "/root/docker.tar.gz"
docker_image_directories:
  - external-hub
  - makina-runway

# timezone && chrony
set_timezone: Asia/Seoul
ntp_client_network: 192.168.135.0/23 # (변수) 환경에 맞는 네트워크 주소 입력 필요
chrony_server: "192.168.135.21" # (변수) 시간 동기화를 위한 IP 변수 ex) master 1번의 IP

# kubeadm-init.yaml create
kubernetes_version: '1.23.17'
dns_domain: cluster.local
service_subnet: 10.96.0.0/12
pod_subnet: 10.244.0.0/16

# DNS wildcard_ip
wildcard_ip: "192.168.135.30" # (변수) metal lb 또는 L4에 ip를 작성해줌 Ingress 용도
main_nameserver: "192.168.135.21" # (변수) nameserver로 사용할 서버의 IP  ex) master 1번의 IP
enable_forwarding: false
forward_servers:
  - "168.126.63.1"
  - "168.126.63.2"
enable_wildcard: true

# helm command && OS package repo
repo_url:
  centos: "http://192.168.135.21:8080/repo" # (변수) 기본 OS repoistory로 사용할 IP ex) master 1번의 IP
  ubuntu: "http://192.168.135.21:8080/repo/" # (변수) 기본 OS repoistory로 사용할 IP ex) master 1번의 IP

base_directory: "/root/makina-runway-1.1.0.1/helm" # (변수) helm chart의 압축이 풀린 디렉토리 위치 
helm_repo_ip: "192.168.135.21:8080" # use http_port # (변수) helm repo로 사용할 IP ex) master 1번의 IP:8080

# Docker 관련 변수
insecure_registries:
  - "harbor.{{ main_domain }}"
  - "cr.makina.rocks"
docker_log_max_size: "2000m"

# Master Node remove taint
remove_taints: true

rook_ceph_values:
  cephClusterSpec:
    dataDirHostPath: /var/lib/rook
    mon:
      count: 3
    storage:
      useAllNodes: true
      useAllDevices: true
    dashboard:
      enabled: true
  operatorNamespace: rook-ceph

# delete_master_node_taint
remove_master_taint: true

# cert_Manager
cert_manager_version: "v1.11.0"
cert_manager_values:
  installCRDs: true
  prometheus:
    enabled: false

# istio_service_type
istio_service_type: "LoadBalancer"

# metalLb-vars
metallb_namespace: metallb-system
metallb_ip_pool_name: default
metallb_l2adv_name: default
metallb_ip_range: "192.168.135.30/32" # (변수) VIP로 사용할 IP 마스터노드와 워커노드에 IP가 아닌 IP 작성하기

# harbor
harbor_values:
  expose:
    tls:
      enabled: false
    type: clusterIP
  externalURLs:
    - "http://harbor.{{ main_domain }}"
  persistence:
    enabled: true
    persistentVolumeClaim:
      registry:
        size: "50Gi"
  trivy:
    enabled: false

# elastic-search replicas
elastic_replicas: 2

#backend
image_registry_url: "http://harbor.{{ main_domain }}/api/v2.0"
image_registry_username: "mrx.dev"
image_registry_password: "klw9pcSDWkpY4udGaGjQP7KrjGoegdIw"
image_registry_api_token: "YWRtaW46SGaFyYm9yMTIzNDU="
grafana_public_url: "grafana.runway.{{ main_domain }}"
runway_url: "runway.{{ main_domain }}"
postgresql_replica_count: "3"
project_shared_volume_storage_class: "ceph-filesystem"
nfs_pv_path: "/nfs" # (변수)  nfs서버로 쓸 mount 경로 작성하기
nfs_pv_server: "master1" # (변수) master 서버 작성
link_instance_max_cpu: "8" # (변수) 최소 노드 크기의 cpu 개수 작성
link_instance_max_memory: "16" # (변수) 최소 노드 크기의 memory 개수 작성
link_instance_max_gpu: "0"
pod_commit_image_repository: "makina-runway/commit-link-"
pip_trusted_host: "pubpypi.makina.rocks" 
pip_index_url: "http://pubpypi.makina.rocks/simple/" 
pgpool_username: "kidi" # (변수) 사용할 계정 db_username
pgpool_password: "kidi" # (변수) 사용할 계정 db_password
backend_tag: "v1.1.0.1" # (변수) 사용할 이미지의 tag 작성

# create_docker_config.json in kubelet, only use public
docker_username: "admin"
docker_password: "Mak1nar0cks!"
docker_registry: "cr.makina.rocks"

# frontend-vars
helm_namespace: "runway" 
global_production: true
image_tag: "v1.1.0.1" # (변수) 사용할 이미지의 tag 작성

#Gpu-operator
gpu_operator_values:
  driver:
    enabled: false
  mig:
    strategy: false
  toolkit:
    enabled: false
  dcgmExporter:
    enabled: true

```

- inventory.ini

```jsx
[masters]
master1 ansible_host=192.168.135.21 #변수  master로 사용할 IP 

[workers]
worker1 ansible_host=192.168.135.22 #변수  worker로 사용할 IP 추가적으로 필요하다면 아래 추가 진행
worker2 ansible_host=192.168.135.23 

[installs]
master1 ansible_host=192.168.135.21 #변수  master로 사용할 IP 

[pre-installs]
master1 ansible_host=192.168.135.21 #변수  master로 사용할 IP 

[all:vars]
ansible_user=root

```

- keygen 생성
    - ssh-keygen 명령어을 입력하고 `Enter` 누르면 keygen이 생성 완료 된다.

```jsx
root@worker2:~# ssh-keygen
Generating public/private rsa key pair.
Enter file in which to save the key (/root/.ssh/id_rsa):
Enter passphrase (empty for no passphrase):
Enter same passphrase again:
Your identification has been saved in /root/.ssh/id_rsa
Your public key has been saved in /root/.ssh/id_rsa.pub
The key fingerprint is:
SHA256:J4ZUWRczi+i40QlMgCFfbYEJB5B7l+aiWg+QRsmuN24 root@worker2
The key's randomart image is:
+---[RSA 3072]----+
|oo+=+=o..o. =.   |
|ooooooo... o +   |
| =.  o+ . . .    |
|+.. +. * .       |
|o+ +  + S .      |
|o.. .  + o       |
|..=.  .          |
|.+E+             |
|o.. .            |
+----[SHA256]-----+

```

- 그리고 설치할 노드에 copy를 진행한다.

```jsx
$ ssh-copy-id <master_node IP>
$ ssh-copy-id <worker_node IP>
```

- 마지막으로 playbook 설치를 진행하면 설치가 끝난다.

```jsx
$ ansible-playbook -i inventory site.yml 
```

### 설치 이후 작업

---

harbor에 계정 생성을 위해  필요한 스크립트 돌리기

- create_harbor_user.sh을 통한 계정생

```jsx
$ chmod +x create_harbor_user.sh
$ ./create_harbor_user.sh
Enter the domain: onboarding1.com <domain.name>

```