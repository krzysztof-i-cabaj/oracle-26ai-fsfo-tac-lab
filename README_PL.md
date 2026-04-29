> [🇬🇧 English](./README.md) | 🇵🇱 Polski

# 🛡️ Oracle 26ai MAA Lab — FSFO + TAC

**Reference implementation laboratorium Maximum Availability Architecture dla Oracle Database 26ai (23.26.1).** RAC 2-node + Active Data Guard + Fast-Start Failover (3-Observer quorum) + Transparent Application Continuity (TAC LEVEL1) — w pełni zautomatyzowane na 5 VM VirtualBox.

![Oracle 26ai](https://img.shields.io/badge/Oracle-26ai_(23.26.1)-F80000?logo=oracle&logoColor=white)
![FSFO](https://img.shields.io/badge/FSFO-Multi--Observer-blue)
![TAC](https://img.shields.io/badge/TAC-LEVEL1_replay-green)
![ADG](https://img.shields.io/badge/Active_DG-RO+APPLY-gold)
![RTO](https://img.shields.io/badge/RTO-%E2%89%A445s-blue)
![RPO](https://img.shields.io/badge/RPO-0-green)
![Tests](https://img.shields.io/badge/Tests-6%2F6_passed-brightgreen)
![License](https://img.shields.io/badge/license-Apache_2.0-blue)
![Docs](https://img.shields.io/badge/docs-bilingual_PL%2FEN-yellow)

---

## 📁 Struktura repo

| Katalog | Co zawiera |
|---|---|
| 📘 [`concept/`](./concept/) | **Koncepcja architektury** — bash, docs, sql, systemd. FSFO + TAC guide jako reference design (19c-baseline z 26ai-aware wariantami). 7 dokumentów (DESIGN, FSFO-GUIDE, TAC-GUIDE, INTEGRATION, FAILOVER-WALKTHROUGH, PLAN, CODE-REVIEW), 12 SQL, 4 bash, 3 systemd unit. |
| 🔧 [`lab/`](./lab/) | **Wdrożenie laboratorium** — kompletna automatyzacja od pustych VM po działający MAA. Kickstart OL8.10, silent GI/DB install, broker, Multi-Observer, TAC service, klient Java UCP. 9 kroków dokumentacji + 19 skryptów + 14 SQL + 5 kickstart configs. |
| 📚 [`legacy/lessons-learned/`](./legacy/lessons-learned/) | **Archiwum knowledge base** — `FIXES_LOG.md` (294 KB, 96 fixów) z pierwszej iteracji środowiska. Materiał edukacyjny — kontrintuicyjne zjawiska Oracle, które prawdopodobnie pojawią się przy odtwarzaniu. |

---

## 🚀 Gdzie zacząć?

| Profil | Punkt wejścia |
|---|---|
| **🏗️ Architekt** — chcę zrozumieć decyzje | [`concept/docs/DESIGN.md`](./concept/docs/DESIGN.md) (8 ADR, kompatybilność, security) |
| **📖 DBA — chcę przeczytać guide** | [`concept/docs/FSFO-GUIDE.md`](./concept/docs/FSFO-GUIDE.md) + [`concept/docs/TAC-GUIDE.md`](./concept/docs/TAC-GUIDE.md) |
| **🔧 Operator — chcę zbudować LAB** | [`lab/README_PL.md`](./lab/README_PL.md) (pre-flight + 9 kroków) lub interaktywnie [`lab/docs/index_PL.html`](./lab/docs/index_PL.html) |
| **🧪 Curious — co z tego wyszło?** | [`lab/docs/test_results_PL.html`](./lab/docs/test_results_PL.html) — 6 scenariuszy testowych, wyniki, lekcje |
| **🐛 Debug — błąd Oracle X** | Najpierw [`legacy/lessons-learned/FIXES_LOG_PL.md`](./legacy/lessons-learned/FIXES_LOG_PL.md) (96 fixów chronologicznie), potem [`lab/EXECUTION_LOG_PL.md`](./lab/EXECUTION_LOG_PL.md) (S01–S28) |
| **📊 Case study** | [`lab/AUTONOMOUS_ACCESS_LOG_PL.md`](./lab/AUTONOMOUS_ACCESS_LOG_PL.md) — 975-linijkowy transcript sesji autonomous testów MAA + Executive Summary |

---

## 📊 Wyniki testów (Sesja S28 · 2026-04-29)

| # | Scenariusz | Status | Najważniejszy fakt |
|---|---|---|---|
| 0 | Pre-flight `validate_env --full` | ✅ | 16 PASS / 0 FAIL — środowisko gotowe |
| 1 | Planowany switchover RAC↔SI | ✅ | TestHarness widział 1× UCP-29, kontynuował na nowym primary |
| 2 | Unplanned FSFO failover | ✅ | **Spontaniczny** podczas testu — auto-failover w trakcie obciążenia |
| 3 | **TAC replay** (kill -9 SPID) | ⭐ | **100/100 INSERT, 0 błędów aplikacji, 0 duplikatów po COMMIT** |
| 4 | Apply Lag exceeded | ⚠️ | Lekcja: `LagLimit=0` chroni Transport, NIE Apply |
| 5 | Master Observer outage | ⚠️ | Explicit promote OK; auto-promote zablokowany przez systemd RestartSec=10s |
| 6 | Final validation — all layers | ✅ | 50 466 wierszy w `test_log`, 0 data loss |

**KPI:** ~90 min autonomous (vs ~6–8h manual) · 6 faktycznych failover · RPO = 0 · 5 bugów (S28-64..S28-68) wykrytych i naprawionych.

➡️ **Pełne wyniki w** - https://krzysztof-i-cabaj.github.io/oracle-26ai-fsfo-tac-lab/test_results.html → wyniki 6 scenariuszy

---

## 🌐 GitHub Pages

- https://krzysztof-i-cabaj.github.io/oracle-26ai-fsfo-tac-lab/ (architektura + 15 kroków)

---

## ✅ Wymagania

- **Oracle Database 26ai (23.26.1)** Enterprise Edition — Primary i Standby (lub 19c z dostosowaniem `concept/sql/*` do `*_19c.sql` wariantów)
- **VirtualBox 7.x** + **35 GB RAM** + **~370 GB storage** dla 5 VM
- **Oracle Linux 8.10** ISO (kickstart auto-install)
- **Diagnostic Pack + Tuning Pack** (dla monitoringu ASH/AWR)
- **Java 17+** (TAC TestHarness — wymaga `--add-opens` dla proxy generation, patrz [legacy FIX-087](./legacy/lessons-learned/FIXES_LOG.md))
- **Active Data Guard option** (read-only standby z apply)

---

## 🔒 Licencjonowanie

| Feature | Licencja |
|---|---|
| Data Guard, DG Broker, FSFO, TAC | Wbudowane w **Enterprise Edition** |
| Active Data Guard (read-only standby) | Opcja **ADG** (oddzielnie) |
| UCP, FAN, Transaction Guard | Brak dodatkowej licencji |

**Środowisko edukacyjne** — Oracle Developer License (lab, brak workloadu produkcyjnego).

Kod skryptów/dokumentacji: **Apache-2.0** (patrz [`LICENSE`](./LICENSE)).

---

## 👤 Autor

**KCB Kris** · Oracle DBA
Pierwsza iteracja: 2026-04-23 · Ostatnia sesja S28: 2026-04-29
