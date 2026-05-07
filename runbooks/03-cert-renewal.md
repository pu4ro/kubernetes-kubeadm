# 03 — 인증서 갱신 / Certificate Renewal

> **언어 / Language:** [한국어](./03-cert-renewal.md) · [English](./03-cert-renewal.en.md)
> **위험도 / Risk:** High · **소요 시간 / Duration:** 15–30분

## 목적 / Purpose

Kubernetes 인증서를 10년 연장하거나 표준 1년 갱신한다. kubeadm이 발급하는 모든 인증서 (`/etc/kubernetes/pki/`) 와 etcd 인증서 포함.

## 위험도 / Risk Level

**High** — API 서버 재시작 발생 (수 초 다운타임). 인증서 손상 시 클러스터가 멈출 수 있어 백업 필수.

## 사전 조건 / Preconditions

- [ ] **`/etc/kubernetes/pki/` 백업** (필수)
  ```bash
  ansible masters -i inventory.ini -m shell \
    -a "sudo tar czf /root/pki-backup-$(date +%s).tgz -C /etc/kubernetes pki"
  ```
- [ ] (HA만) `make check-etcd-health` — 3/3 정상
- [ ] 만료 사전 확인:
  ```bash
  ansible masters -i inventory.ini -m shell -a "kubeadm certs check-expiration"
  ```

### 만료 출력 해석 예시
```
CERTIFICATE                EXPIRES                  RESIDUAL TIME   ...
admin.conf                 Apr 15, 2027 12:00 UTC   354d            ...
apiserver                  Apr 15, 2027 12:00 UTC   354d            ...
apiserver-etcd-client      Apr 15, 2027 12:00 UTC   354d            ...
apiserver-kubelet-client   Apr 15, 2027 12:00 UTC   354d            ...
controller-manager.conf    Apr 15, 2027 12:00 UTC   354d            ...
etcd-healthcheck-client    Apr 15, 2027 12:00 UTC   354d            ...
etcd-peer                  Apr 15, 2027 12:00 UTC   354d            ...
etcd-server                Apr 15, 2027 12:00 UTC   354d            ...
front-proxy-client         Apr 15, 2027 12:00 UTC   354d            ...
scheduler.conf             Apr 15, 2027 12:00 UTC   354d            ...
```
모든 RESIDUAL TIME이 30d 이상 권장. 미만이면 즉시 갱신.

## 시나리오 1 — 10년 연장 (`extend_k8s_certs`)

`extend_k8s_certs` role이 인증서를 10년 유효로 재생성. 신규 클러스터 또는 정기 갱신 시 추천.

### 절차

```bash
# 1. group_vars/all.yml 확인 (이미 기본값)
# extend_k8s_certificates: true

# 2. 실행
make tag-certs
# 또는
ansible-playbook -i inventory.ini site.yml --tags k8s-certs
```

### Role 동작
1. `/etc/kubernetes/pki/`의 기존 인증서 백업 (`.bak`)
2. `kubeadm certs renew all` 실행 (각 마스터)
3. controller-manager, scheduler, etcd 컨테이너 자동 재시작 (Pod 재생성)
4. API 서버 재시작 (~30초 다운타임)

### 검증
```bash
ansible masters -i inventory.ini -m shell -a "kubeadm certs check-expiration"
# 모든 RESIDUAL TIME이 ~3650d (10년)

make check-cluster
make validate
```

## 시나리오 2 — 표준 1년 갱신 (`kubeadm certs renew`)

10년 연장을 사용하지 않고 표준 절차로 1년 갱신.

```bash
# 각 마스터에서 (한 번에 하나씩 안전)
ssh master1 "sudo kubeadm certs renew all"
ssh master1 "sudo systemctl restart kubelet"

# kubectl 인증 갱신
ssh master1 "sudo cp /etc/kubernetes/admin.conf ~/.kube/config && sudo chown \$(id -u):\$(id -g) ~/.kube/config"

# HA의 다른 마스터도 동일하게
ssh master2 "sudo kubeadm certs renew all && sudo systemctl restart kubelet"
ssh master3 "sudo kubeadm certs renew all && sudo systemctl restart kubelet"
```

### 워커 노드 kubelet 인증서
워커는 `rotate-certificates: true` 설정 시 자동 갱신됨. 수동 갱신:
```bash
ansible workers -i inventory.ini -m systemd -a "name=kubelet state=restarted"
```

## 검증 / Verification

```bash
# 1. 모든 인증서 만료일
ansible masters -i inventory.ini -m shell -a "kubeadm certs check-expiration"

# 2. API 서버 응답
make check-cluster
kubectl get nodes

# 3. 5단계 헬스체크
make validate

# 4. (선택) etcd 인증서 직접 확인
ssh master1 "sudo openssl x509 -in /etc/kubernetes/pki/etcd/server.crt -noout -dates"
```

## 롤백 / Rollback

### 방법 1: 자동 백업 사용
`extend_k8s_certs` role이 자동으로 `.bak` 파일 생성. 갱신 직후 문제 시:
```bash
ssh master1
ls /etc/kubernetes/pki/*.bak
sudo cp /etc/kubernetes/pki/apiserver.crt.bak /etc/kubernetes/pki/apiserver.crt
sudo cp /etc/kubernetes/pki/apiserver.key.bak /etc/kubernetes/pki/apiserver.key
# ... 나머지 파일
sudo systemctl restart kubelet
```

### 방법 2: 사전 백업 tar 파일 사용
사전에 만든 `pki-backup-*.tgz`로 복원:
```bash
ssh master1
sudo tar xzf /root/pki-backup-<timestamp>.tgz -C /etc/kubernetes
sudo systemctl restart kubelet
```

### 방법 3: 클러스터 손상 시 재구축
인증서 복구가 안 되면 [06 클러스터 리셋](./06-cluster-reset.md).

## 자주 묻는 질문 / FAQ

### Q1. 인증서 갱신 후 `kubectl`이 동작 안 함.
A. `~/.kube/config`도 새 인증서로 갱신 필요:
```bash
ssh master1
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
kubectl cluster-info
```

### Q2. HA 클러스터에서 마스터별로 갱신 시 etcd가 깨질까요?
A. `kubeadm certs renew all`은 etcd 인증서도 함께 갱신하므로 정상 동작. 다만 한 번에 한 마스터씩 진행하고, 매번 `make check-etcd-health`로 확인 권장.

### Q3. 만료된 인증서로 시작하는 클러스터를 살릴 수 있나요?
A. 가능. 단, kubelet 통신용 client 인증서가 만료되면 kubelet이 시작 안 됨. 절차:
1. master1에 SSH
2. `sudo kubeadm certs renew all`
3. `sudo systemctl restart kubelet containerd`
4. 다른 마스터/워커도 순차 진행

### Q4. CA 인증서도 갱신해야 하나요?
A. CA는 기본 10년 (kubeadm 기본값). `kubeadm certs renew all`은 CA를 갱신하지 않음. CA 갱신은 클러스터 재구축에 가까운 작업이므로 별도 계획 필요.

### Q5. `extend_k8s_certificates: true`인데 만료가 1년으로 나옵니다.
A. role이 실행되지 않은 가능성. 명시적으로:
```bash
make tag-certs
# 출력 확인
make cmd-masters CMD="kubeadm certs check-expiration | head -3"
```

## 관련 문서 / Related docs

- [04 노드 IP 변경](./04-node-ip-change.md) (`update-ip-with-certs`)
- [06 클러스터 리셋](./06-cluster-reset.md)
- `roles/extend_k8s_certs/`
- [kubeadm 공식 문서: Certificate Management](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/)
