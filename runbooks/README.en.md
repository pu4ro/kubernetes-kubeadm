# Operational Runbooks

> **Language / 언어:** [한국어](./README.md) · [English](./README.en.md)
> **Status / 상태:** Draft (content to be authored in Phase 5)

Standard Operating Procedures (SOPs) operators follow when installing, maintaining, or recovering the Kubernetes cluster.

## Scenario index

| # | Runbook | Risk | Duration | 한국어 | English |
|---|---|---|---|---|---|
| 00 | Prerequisites | Low | 30–60 min | [00-prerequisites.md](./00-prerequisites.md) | [00-prerequisites.en.md](./00-prerequisites.en.md) |
| 01 | Day-0 install (Online / Offline / HA) | Medium | 30–90 min | [01-day0-install.md](./01-day0-install.md) | [01-day0-install.en.md](./01-day0-install.en.md) |
| 02 | Add / remove worker nodes | Medium | 15–30 min | [02-add-worker.md](./02-add-worker.md) | [02-add-worker.en.md](./02-add-worker.en.md) |
| 03 | Certificate renewal (10y extend / 1y renew) | High | 15–30 min | [03-cert-renewal.md](./03-cert-renewal.md) | [03-cert-renewal.en.md](./03-cert-renewal.en.md) |
| 04 | Node IP change (single / HA) | High | 30–90 min | [04-node-ip-change.md](./04-node-ip-change.md) | [04-node-ip-change.en.md](./04-node-ip-change.en.md) |
| 05 | Incident response (NotReady / etcd / CNI / registry) | varies | immediate | [05-incident-response.md](./05-incident-response.md) | [05-incident-response.en.md](./05-incident-response.en.md) |
| 06 | Cluster reset / redeploy | High | 15–60 min | [06-cluster-reset.md](./06-cluster-reset.md) | [06-cluster-reset.en.md](./06-cluster-reset.en.md) |

## Risk levels

| Level | Definition | Examples |
|---|---|---|
| **Low** | Idempotent, local impact only, no cluster downtime even on failure | `make ping`, `make validate` |
| **Medium** | Mutates cluster state, may affect some workloads | Add worker, reconfigure CNI |
| **High** | Touches etcd / certs / IPs / disks; mistakes can break the cluster | IP change, cert regeneration, disk format |

**Every High-risk runbook contains an explicit rollback section.** Before starting, review the [backup recommendations](./00-prerequisites.en.md#backup-recommendations).

## Common runbook template

Every runbook follows this 9-section structure:

1. **Purpose** — one paragraph
2. **Preconditions** — checklist with verification commands
3. **Risk level** — Low / Medium / High
4. **Estimated duration** — measured range
5. **Procedure** — exact commands with expected output
6. **Verification** — `make validate` + scenario-specific checks
7. **Rollback** — required for High-risk operations
8. **FAQ** — at least 3 real friction points
9. **Related docs** — links

## Getting started

- **First-time install**: [00 Prerequisites](./00-prerequisites.en.md) → [01 Day-0 install](./01-day0-install.en.md)
- **Add a node**: [02 Add worker](./02-add-worker.en.md)
- **Something broke**: [05 Incident response](./05-incident-response.en.md) (search by symptom first)
- **Periodic ops**: [03 Cert renewal](./03-cert-renewal.en.md), [04 IP change](./04-node-ip-change.en.md)

## Related docs

- [README.md](../README.md) — Project overview and quick start (Korean)
- [README.en.md](../README.en.md) — Project overview and quick start (English)
- [group_vars/all.yml.example](../group_vars/all.yml.example) — All variables with detailed comments
