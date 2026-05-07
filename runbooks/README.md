# Operational Runbooks

> **언어 / Language:** [한국어](./README.md) · [English](./README.en.md)
> **상태 / Status:** Draft (Phase 5에서 본문 작성 예정)

운영자가 Kubernetes 클러스터를 설치·유지·복구할 때 단계별로 따라갈 수 있는 SOP(Standard Operating Procedure) 문서 모음입니다.

## 시나리오 목록

| # | Runbook | 위험도 | 소요시간 | 한국어 | English |
|---|---|---|---|---|---|
| 00 | 사전 준비 (Prerequisites) | Low | 30–60분 | [00-prerequisites.md](./00-prerequisites.md) | [00-prerequisites.en.md](./00-prerequisites.en.md) |
| 01 | Day-0 설치 (Online / Offline / HA) | Medium | 30–90분 | [01-day0-install.md](./01-day0-install.md) | [01-day0-install.en.md](./01-day0-install.en.md) |
| 02 | Worker 노드 추가/제거 | Medium | 15–30분 | [02-add-worker.md](./02-add-worker.md) | [02-add-worker.en.md](./02-add-worker.en.md) |
| 03 | 인증서 갱신 (10년 연장 / 1년 갱신) | High | 15–30분 | [03-cert-renewal.md](./03-cert-renewal.md) | [03-cert-renewal.en.md](./03-cert-renewal.en.md) |
| 04 | 노드 IP 변경 (단일 / HA) | High | 30–90분 | [04-node-ip-change.md](./04-node-ip-change.md) | [04-node-ip-change.en.md](./04-node-ip-change.en.md) |
| 05 | 장애 대응 (NotReady / etcd / CNI / 레지스트리) | varies | 즉시 | [05-incident-response.md](./05-incident-response.md) | [05-incident-response.en.md](./05-incident-response.en.md) |
| 06 | 클러스터 리셋·재배포 | High | 15–60분 | [06-cluster-reset.md](./06-cluster-reset.md) | [06-cluster-reset.en.md](./06-cluster-reset.en.md) |

## 위험도 정의

| 등급 | 정의 | 예시 |
|---|---|---|
| **Low** | 멱등, 로컬 영향만, 실패해도 클러스터 무중단 | `make ping`, `make validate` |
| **Medium** | 클러스터 상태 변경, 일부 워크로드 영향 가능 | Worker 추가, CNI 재설정 |
| **High** | etcd / 인증서 / IP / 디스크 등 핵심 컴포넌트 변경, 잘못 시 클러스터 손상 | IP 변경, 인증서 재생성, 디스크 포맷 |

**모든 High 위험 작업은 롤백 절차가 명시되어 있습니다.** 작업 전 반드시 [백업 권장사항](./00-prerequisites.md#백업-권장사항) 섹션을 확인하세요.

## 모든 Runbook 공통 템플릿

각 runbook은 다음 9개 섹션 구조를 따릅니다:

1. **목적 / Purpose** — 한 문단 설명
2. **사전 조건 / Preconditions** — 검증 명령 포함 체크리스트
3. **위험도 / Risk level** — Low / Medium / High
4. **소요 시간 / Estimated duration** — 실제 측정 범위
5. **절차 / Procedure** — 정확한 명령 + 예상 출력
6. **검증 / Verification** — `make validate` + 시나리오별 추가 검사
7. **롤백 / Rollback** — High 위험 작업은 필수
8. **자주 묻는 질문 / FAQ** — 실제 막혔던 지점 최소 3개
9. **관련 문서 / Related docs** — 링크

## 시작 가이드

- **처음 클러스터를 설치한다면**: [00 사전 준비](./00-prerequisites.md) → [01 Day-0 설치](./01-day0-install.md)
- **클러스터에 노드를 추가하려면**: [02 Worker 추가](./02-add-worker.md)
- **장애가 발생했다면**: [05 장애 대응](./05-incident-response.md) (먼저 증상으로 검색)
- **운영 환경 점검 주기 작업**: [03 인증서 갱신](./03-cert-renewal.md), [04 IP 변경](./04-node-ip-change.md)

## 관련 문서

- [README.md](../README.md) — 프로젝트 개요 및 빠른 시작
- [group_vars/all.yml.example](../group_vars/all.yml.example) — 모든 변수 상세 주석
