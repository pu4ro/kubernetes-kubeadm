# Operational Runbooks

운영 절차는 *위험도*별 3개 파일로 정리됩니다. 시작 전에 `make ping`으로 SSH 연결을 확인하고, 모든 검증은 `make validate`로 수렴합니다.

| 위험도 | 파일 | 다루는 시나리오 | 소요 시간 | 롤백 |
|---|---|---|---|---|
| **Low** | [daily-ops.md](./daily-ops.md) | Worker 추가/제거, 노드 상태 확인, validation | 5–30분 | 자동 idempotent |
| **Medium** | [risky-ops.md](./risky-ops.md) | 노드 IP 변경 (단일/HA), 인증서 갱신, 오프라인 ↔ 온라인 전환 | 30–90분 | 명시 |
| **High** | [recovery.md](./recovery.md) | NotReady, etcd 복구, CNI 장애, registry 장애, OIDC 장애, 전체 reset | 가변 | 필수 (각 항목별) |

## 공통 사항

- **사전 준비:** `make ping` 통과, `group_vars/all.yml` 최신화, `inventory.ini` 정확.
- **위험도 표기:** Low = idempotent · cluster 상태 미변경, Medium = cluster 상태 변경 · 가역적, High = 데이터/연결성 영향 가능 · 롤백 필수.
- **검증:** `make validate` (모든 운영 후) + 항목별 추가 명령 (etcd/CNI 등).
- **실패 시 우선 진단:** `make check-cluster` → `journalctl -u kubelet -f` → 항목별 runbook의 *실패 시* 항목.

## 사용 흐름

1. 위 표에서 위험도 → 시나리오 매칭.
2. 해당 파일 내 H2 시나리오에서 `사전 점검 → 절차 → 검증 → 실패 시 → 롤백` 순서대로 진행.
3. 완료 후 `make validate` 통과 확인.

## 관련 문서

- 변수 참조: [`../group_vars/all.yml.example`](../group_vars/all.yml.example)
- Makefile 명령 요약: [`../README.md`](../README.md#makefile-명령)
- legacy 심층 가이드: [`../ADD-WORKER-GUIDE.md`](../ADD-WORKER-GUIDE.md), [`../CONTAINERD-CUSTOM-PATH.md`](../CONTAINERD-CUSTOM-PATH.md), [`../MAKEFILE-GUIDE.md`](../MAKEFILE-GUIDE.md)
