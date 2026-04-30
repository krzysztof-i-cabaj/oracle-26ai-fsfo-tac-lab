> 🇬🇧 English | [🇵🇱 Polski](./README_PL.md)

# 🛡️ Oracle 26ai MAA Lab — FSFO + TAC

**Reference implementation lab for Oracle Database 26ai (23.26.1) Maximum Availability Architecture.** 2-node RAC + Active Data Guard + Fast-Start Failover (3-Observer quorum) + Transparent Application Continuity (TAC LEVEL1) — fully automated on 5 VirtualBox VMs.

![Oracle 26ai](https://img.shields.io/badge/Oracle-26ai_(23.26.1)-F80000?logo=oracle&logoColor=white)
![FSFO](https://img.shields.io/badge/FSFO-Multi--Observer-blue)
![TAC](https://img.shields.io/badge/TAC-LEVEL1_replay-green)
![ADG](https://img.shields.io/badge/Active_DG-RO+APPLY-gold)
![RTO](https://img.shields.io/badge/RTO-%E2%89%A445s-blue)
![RPO](https://img.shields.io/badge/RPO-0-green)
![Tests](https://img.shields.io/badge/Tests-6%2F6_passed-brightgreen)
![License](https://img.shields.io/badge/license-Apache_2.0-blue)
![Docs](https://img.shields.io/badge/docs-bilingual_EN%2FPL-yellow)

---

## 📁 Repo structure

| Directory | Contents |
|---|---|
| 📘 [`concept/`](./concept/) | **Architecture concept** — bash, docs, sql, systemd. FSFO + TAC guide as reference design (19c baseline with 26ai-aware variants). 7 documents (DESIGN, FSFO-GUIDE, TAC-GUIDE, INTEGRATION, FAILOVER-WALKTHROUGH, PLAN, CODE-REVIEW), 12 SQL, 4 bash, 3 systemd units. |
| 🔧 [`lab/`](./lab/) | **Lab deployment** — full automation from empty VMs to working MAA. OL 8.10 kickstart, silent GI/DB install, broker, Multi-Observer, TAC service, Java UCP client. 9 documentation steps + 19 scripts + 14 SQL + 5 kickstart configs. |
| 📚 [`legacy/lessons-learned/`](./legacy/lessons-learned/) | **Knowledge base archive** — `FIXES_LOG.md` (294 KB, 96 fixes) from the first environment iteration. Educational material — counter-intuitive Oracle behaviors likely to resurface during reproduction. |

---

## 🚀 Where to start?

| Profile | Entry point |
|---|---|
| **🏗️ Architect** — I want to understand the decisions | [`concept/docs/DESIGN.md`](./concept/docs/DESIGN.md) (8 ADRs, compatibility, security) |
| **📖 DBA — I want to read the guide** | [`concept/docs/FSFO-GUIDE.md`](./concept/docs/FSFO-GUIDE.md) + [`concept/docs/TAC-GUIDE.md`](./concept/docs/TAC-GUIDE.md) |
| **🔧 Operator — I want to build the lab** | [`lab/README.md`](./lab/README.md) (pre-flight + 9 steps) or interactively [`architecture + 15 steps`](https://krzysztof-i-cabaj.github.io/oracle-26ai-fsfo-tac-lab/index.html) |
| **🧪 Curious — what came out of this?** | [`lab/docs/test_results.html`](./lab/docs/test_results.html) — 6 test scenarios, results, lessons |
| **🐛 Debug — Oracle error X** | Start with [`legacy/lessons-learned/FIXES_LOG.md`](./legacy/lessons-learned/FIXES_LOG.md) (96 fixes chronologically), then [`lab/EXECUTION_LOG.md`](./lab/EXECUTION_LOG.md) (S01–S28) |
| **📊 Case study** | [`lab/AUTONOMOUS_ACCESS_LOG.md`](./lab/AUTONOMOUS_ACCESS_LOG.md) — 975-line transcript of an autonomous MAA test session + Executive Summary |

> **Note on translations:** Tier 1 entry pages (this README, `lab/docs/index.html`, `lab/docs/test_results.html`, `lab/README.md`, `concept/README.md`) are available in both English and Polish. Other documentation is being progressively translated; until then, the linked files may render in Polish on GitHub. Polish-only files end with `_PL.md`.

---

## 📊 Test results (Session S28 · 2026-04-29)

| # | Scenario | Status | Key takeaway |
|---|---|---|---|
| 0 | Pre-flight `validate_env --full` | ✅ | 16 PASS / 0 FAIL — environment ready |
| 1 | Planned RAC↔SI switchover | ✅ | TestHarness saw a single UCP-29, continued on the new primary |
| 2 | Unplanned FSFO failover | ✅ | **Spontaneous** during the test — auto-failover under load |
| 3 | **TAC replay** (`kill -9` of SPID) | ⭐ | **100/100 INSERTs, 0 application errors, 0 duplicates after COMMIT** |
| 4 | Apply Lag exceeded | ⚠️ | Lesson: `LagLimit=0` protects Transport, NOT Apply |
| 5 | Master Observer outage | ⚠️ | Explicit promote OK; auto-promote blocked by systemd `RestartSec=10s` |
| 6 | Final validation — all layers | ✅ | 50,466 rows in `test_log`, 0 data loss |

**KPIs:** ~90 min autonomous (vs ~6–8 h manual) · 6 actual failovers · RPO = 0 · 5 bugs (S28-64..S28-68) detected and fixed.

➡️ [**Full results**](https://krzysztof-i-cabaj.github.io/oracle-26ai-fsfo-tac-lab/test_results.html) → results from 6 scenarios

---

## ✅ Requirements

- **Oracle Database 26ai (23.26.1)** Enterprise Edition — Primary and Standby (or 19c with `concept/sql/*` adapted to the `*_19c.sql` variants)
- **VirtualBox 7.x** + **35 GB RAM** + **~370 GB storage** for 5 VMs
- **Oracle Linux 8.10** ISO (kickstart auto-install)
- **Diagnostic Pack + Tuning Pack** (for ASH/AWR monitoring)
- **Java 17+** (TAC TestHarness — requires `--add-opens` for proxy generation, see [legacy FIX-087](./legacy/lessons-learned/FIXES_LOG.md))
- **Active Data Guard option** (read-only standby with apply)

---

## 🔒 Licensing

| Feature | License |
|---|---|
| Data Guard, DG Broker, FSFO, TAC | Built into **Enterprise Edition** |
| Active Data Guard (read-only standby) | Separate **ADG** option |
| UCP, FAN, Transaction Guard | No additional licensing |

**Educational environment** — Oracle Developer License (lab, no production workload).

Script and documentation source: **Apache-2.0** (see [`LICENSE`](./LICENSE)).

---

## 👤 Author

**KCB Kris** · Oracle DBA
First iteration: 2026-04-23 · Latest session S28: 2026-04-29
