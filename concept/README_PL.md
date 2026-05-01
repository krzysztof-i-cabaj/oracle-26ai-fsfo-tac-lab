> [🇬🇧 English](./README.md) | 🇵🇱 Polski

> 📘 **Część `concept/`** repo Oracle 26ai MAA Lab. Tu jest **koncepcja architektury** (FSFO + TAC, 19c-baseline, z 26ai-aware wariantami SQL).
> Faktyczne wdrożenie LAB-a w siostrzanym katalogu [`../lab/`](../lab/).
> Top-level README repo: [`../README_PL.md`](../README_PL.md).

---

# 🛡️ FSFO + TAC Guide — Oracle 19c (3-site RAC + Data Guard)

![Oracle 19c](https://img.shields.io/badge/Oracle-19c-F80000?logo=oracle&logoColor=white)
![FSFO](https://img.shields.io/badge/FSFO-Fast--Start%20Failover-blue)
![TAC](https://img.shields.io/badge/TAC-Transparent%20Application%20Continuity-green)
![RTO](https://img.shields.io/badge/RTO-%E2%89%A445s-blue)
![RPO](https://img.shields.io/badge/RPO-0-green)
![Status](https://img.shields.io/badge/status-v1.0-brightgreen)
![License](https://img.shields.io/badge/license-Apache%202.0-blue)
![Docs](https://img.shields.io/badge/docs-bilingual%20PL%2FEN-yellow)

**Kompletny poradnik wdrożenia Fast-Start Failover (FSFO) oraz Transparent Application Continuity (TAC) dla Oracle Database 19c w topologii 3-site (MAA).**

**Complete deployment guide for Oracle 19c Fast-Start Failover (FSFO) and Transparent Application Continuity (TAC) in 3-site topology (MAA).**

---

## 📋 Architektura docelowa / Target architecture

| Ośrodek / Site | Rola / Role | Konfiguracja / Configuration |
|----------------|-------------|------------------------------|
| **DC**  | PRIMARY | 2-node RAC, baza `PRIM`, Observer `obs_dc` (backup) |
| **DR**  | STANDBY | 2-node RAC, baza `STBY`, Observer `obs_dr` (backup) |
| **EXT** | Observer | Master Observer `obs_ext` (brak bazy; dedykowany host) |

**Protection Mode:** MAX AVAILABILITY (SYNC DC↔DR, z SRL, AFFIRM)
**Failover Threshold:** 30 s | **Lag Limit:** 30 s | **Auto-Reinstate:** TRUE

---

## 📁 Struktura projektu / Project structure

```
20260423-FSFO-TAC-guide/
├── README.md                   # ← ten plik / this file
├── LICENSE                     # Apache-2.0
├── .gitignore
├── checklist.html              # Interaktywna checklista HTML (Arch + 3 checklists + Timeline + Risk Matrix)
├── targets.lst                 # Lista baz dla validate_all.sh
│
├── docs/                       # Dokumentacja projektu — 7 plików .md
│   ├── DESIGN.md                       # Architektura, ADR, kompatybilność, security
│   ├── PLAN.md                         # Plan 6-fazowy Weeks 1-13+
│   ├── FSFO-GUIDE.md                   # Poradnik FSFO (11 sekcji)
│   ├── TAC-GUIDE.md                    # Poradnik TAC (10 sekcji)
│   ├── INTEGRATION-GUIDE.md            # FSFO+TAC razem (8 sekcji)
│   ├── FAILOVER-WALKTHROUGH.md         # Edukacyjny walkthrough (6 aktorów, 5 faz, t=0s→t=45s)
│   └── CODE-REVIEW-REPORT.md           # Przykładowy review (82→97/100) — wartość edukacyjna
│
├── sql/                        # Skrypty SQL (uruchamiane przez sqlconn.sh) — 8 plików
│   ├── fsfo_broker_status.sql        # Status brokera i FSFO (5 sekcji)
│   ├── fsfo_check_readiness.sql      # FSFO pre-deployment readiness (6 sekcji)
│   ├── fsfo_configure_broker.sql     # Generator komend dgmgrl
│   ├── fsfo_monitor.sql              # Ciągły monitoring FSFO+TAC (7 sekcji)
│   ├── tac_configure_service_rac.sql # Konfiguracja TAC service (srvctl + DBMS_SERVICE)
│   ├── tac_full_readiness.sql        # TAC pełny readiness check (12 sekcji)
│   ├── tac_replay_monitor.sql        # Monitoring replay TAC (6 sekcji)
│   └── validate_environment.sql      # 12 checks FSFO+TAC combined
│
├── bash/                       # Skrypty powłoki — 4 pliki
│   ├── fsfo_setup.sh                 # Orkiestrator setupu FSFO
│   ├── fsfo_monitor.sh               # Health monitor (cron-friendly, tryb -a)
│   ├── tac_deploy.sh                 # Deployment TAC service
│   └── validate_all.sh               # Pełna walidacja multi-DB
│
└── systemd/                    # Unity systemd dla Observer HA — 3 pliki
    ├── dgmgrl-observer-dc.service
    ├── dgmgrl-observer-dr.service
    └── dgmgrl-observer-ext.service
```

---

## 🚀 Quick Reference / Ściągawka

### FSFO commands (dgmgrl)

```
ENABLE:    ENABLE FAST_START FAILOVER
DISABLE:   DISABLE FAST_START FAILOVER
STATUS:    SHOW FAST_START FAILOVER
OBSERVER:  START OBSERVER <name> IN BACKGROUND FILE '/path/obs.dat'
STOP OBS:  STOP OBSERVER <name>
SWITCH:    SWITCHOVER TO <standby_db>
FAILOVER:  FAILOVER TO <standby_db> [IMMEDIATE]
REINSTATE: REINSTATE DATABASE <old_primary>
```

### Key properties (FastStartFailover)

```
FastStartFailoverThreshold     = 30   (seconds)
FastStartFailoverLagLimit      = 30   (seconds)
FastStartFailoverAutoReinstate = TRUE
ObserverOverride               = TRUE
ObserverReconnect              = 10   (seconds)
```

### Toolkit

```bash
# Pre-deployment readiness check (FSFO)
sqlconn.sh -s PRIM -f sql/fsfo_check_readiness.sql

# Pre-deployment readiness check (TAC, 12 sekcji)
sqlconn.sh -s PRIM -f sql/tac_full_readiness.sql

# FSFO setup (dry-run)
bash/fsfo_setup.sh -s PRIM -d

# Health monitor (alert mode for cron)
bash/fsfo_monitor.sh -s PRIM -a

# TAC replay monitoring
sqlconn.sh -s PRIM -f sql/tac_replay_monitor.sql

# Multi-DB validation
bash/validate_all.sh -l targets.lst

# Interaktywna checklista wdrożeniowa
# Otwórz w przeglądarce: checklist.html
```

---

## 📖 Gdzie zacząć? / Where to start?

| Cel / Goal | Dokument |
|------------|----------|
| Szybka wizualizacja postępu + Timeline + Risk Matrix | [Checklist (concept · 19c · 3-site)](https://krzysztof-i-cabaj.github.io/oracle-26ai-fsfo-tac-lab/checklist_PL.html)|
| Przegląd architektury i decyzji (ADR) | [docs/DESIGN.md](docs/DESIGN.md) |
| Harmonogram wdrożenia (6 faz, 13+ tygodni) | [docs/PLAN.md](docs/PLAN.md) |
| Wdrożenie FSFO krok po kroku | [docs/FSFO-GUIDE.md](docs/FSFO-GUIDE.md) |
| Konfiguracja TAC (UCP, FAN, Transaction Guard) | [docs/TAC-GUIDE.md](docs/TAC-GUIDE.md) |
| Failover end-to-end (FSFO→FAN→UCP→replay) | [docs/INTEGRATION-GUIDE.md](docs/INTEGRATION-GUIDE.md) |
| Edukacyjny walkthrough diagramu failoveru (6 aktorów, 5 faz) | [docs/FAILOVER-WALKTHROUGH.md](docs/FAILOVER-WALKTHROUGH.md) |
| Przykład code review (82→97/100) — proces krytycznej analizy | [docs/CODE-REVIEW-REPORT.md](docs/CODE-REVIEW-REPORT.md) |

---

## ✅ Wymagania / Requirements

- Oracle Database **19c Enterprise Edition** na PRIM i STBY
- **SQLcl 25.2+** lub **sqlplus** w `PATH`
- **sqlconn.sh** w `PATH` (z projektu `20260130-sqlconn`) — wszystkie skrypty bash wołają `sqlconn.sh` bezpośrednio
- **Diagnostic Pack + Tuning Pack** (dla monitoringu ASH/AWR)
- Host dla Observer na **EXT** (dedykowany, z `dgmgrl` i walletem)
- **Java UCP 19c+** + **ojdbc11.jar** po stronie aplikacji (dla TAC)

---

## 🔒 Licencjonowanie / Licensing

| Feature | Licencja / License |
|---------|-------------------|
| Data Guard, DG Broker, FSFO, TAC | Wbudowane w **Enterprise Edition** |
| Active Data Guard (read-only standby) | Opcja **ADG** (oddzielnie) |
| UCP, FAN, Transaction Guard | Brak dodatkowej licencji |

Szczegóły w [docs/INTEGRATION-GUIDE.md § 8 Licensing Summary](docs/INTEGRATION-GUIDE.md#8-licensing-summary).

---

## 👤 Autor / Author

**KCB Kris**
Data utworzenia: 2026-04-23
Wersja: 1.0

**Related:** [docs/FSFO-GUIDE.md](docs/FSFO-GUIDE.md) • [docs/TAC-GUIDE.md](docs/TAC-GUIDE.md) • [docs/INTEGRATION-GUIDE.md](docs/INTEGRATION-GUIDE.md) • [docs/PLAN.md](docs/PLAN.md) • [docs/DESIGN.md](docs/DESIGN.md)
