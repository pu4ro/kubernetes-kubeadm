# CoreDNS Hosts Configuration Role

이 역할은 Kubernetes CoreDNS에 호스트 엔트리를 추가하여 클러스터 내에서 사용자 정의 도메인 해상도를 가능하게 합니다.

## 기능

- `group_vars/all.yml`의 `registry_hosts` 설정을 CoreDNS에 자동 추가
- 추가 사용자 정의 호스트 엔트리 지원
- 조건부 실행 (true/false 토글)
- 태그 기반 실행 지원
- CoreDNS ConfigMap 자동 업데이트 및 pods 재시작

## 사용법

### 1. 변수 설정

`group_vars/all.yml`에서 다음 변수를 설정:

```yaml
# CoreDNS 호스트 설정 활성화/비활성화
configure_coredns_hosts: true

# 레지스트리 호스트 (기존 설정)
registry_hosts:
  "harbor.runway.test": "192.168.135.28"
  "registry.local": "10.0.0.100"
```

역할별 추가 설정은 `roles/configure_coredns_hosts/defaults/main.yml`에서 확인:

```yaml
# 추가 사용자 정의 호스트
custom_coredns_hosts:
  example.local: "192.168.1.100"
  test.domain.com: "10.0.0.1"
```

### 2. 실행 방법

#### 전체 플레이북 실행시 조건부 실행:
```bash
# configure_coredns_hosts: true일 때만 실행됨
ansible-playbook -i inventory.ini site.yml
```

#### 태그로 특정 실행:
```bash
# CoreDNS 호스트 설정만 실행
ansible-playbook -i inventory.ini site.yml --tags coredns-hosts

# 다른 태그와 함께 실행
ansible-playbook -i inventory.ini site.yml --tags "kubernetes,coredns-hosts"
```

#### 변수 오버라이드로 강제 실행:
```bash
# configure_coredns_hosts가 false여도 강제 실행
ansible-playbook -i inventory.ini site.yml --tags coredns-hosts -e "configure_coredns_hosts=true"
```

## 작동 방식

1. **조건 확인**: `configure_coredns_hosts` 변수가 true인지 확인
2. **환경 검증**: kubectl 가용성 및 CoreDNS ConfigMap 존재 확인
3. **호스트 수집**: `registry_hosts`와 `custom_coredns_hosts` 병합
4. **Corefile 생성**: 새로운 Corefile 템플릿 생성 (hosts 플러그인 포함)
5. **ConfigMap 업데이트**: CoreDNS ConfigMap 업데이트
6. **Pod 재시작**: CoreDNS pods 재시작으로 설정 적용
7. **상태 확인**: CoreDNS pods 준비 상태 대기

## 주의사항

- 이 역할은 master 노드에서만 실행됩니다 (`hosts: masters`)
- Kubernetes 클러스터가 정상 동작하는 상태에서만 실행 가능
- `kubernetes.core` Ansible collection이 필요합니다
- CoreDNS pods가 재시작되므로 잠시 DNS 해상도가 중단될 수 있습니다

## 예제

### group_vars/all.yml 설정
```yaml
configure_coredns_hosts: true
registry_hosts:
  "harbor.runway.test": "192.168.135.28"
  "registry.internal": "10.0.0.50"
```

### 결과 Corefile
```
.:53 {
    errors
    health {
       lameduck 5s
    }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
       pods insecure
       fallthrough in-addr.arpa ip6.arapa
       ttl 30
    }
    hosts {
        192.168.135.28 harbor.runway.test
        10.0.0.50 registry.internal
        fallthrough
    }
    prometheus :9153
    forward . /etc/resolv.conf {
       max_concurrent 1000
    }
    cache 30
    loop
    reload
    loadbalance
}
```