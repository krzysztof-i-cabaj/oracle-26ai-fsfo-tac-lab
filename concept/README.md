> 🇬🇧 English | [🇵🇱 Polski](./README_PL.md)

> 📘 **The `concept/` part** of the Oracle 26ai MAA Lab repo. This is the **architecture concept** (FSFO + TAC, 19c baseline, with 26ai-aware SQL variants).
> The actual lab deployment lives in the sibling [`../lab/`](../lab/) directory.
> Top-level README of the repo: [`../README.md`](../README.md).

---

# 🛡️ FSFO + TAC Guide — Oracle 19c (3-site RAC + Data Guard)

![Oracle 19c](https://img.shields.io/badge/Oracle-19c-F80000?logo=oracle&logoColor=white)
![FSFO](https://img.shields.io/badge/FSFO-Fast--Start%20Failover-blue)
![TAC](https://img.shields.io/badge/TAC-Transparent%20Application%20Continuity-green)
![RTO](https://img.shields.io/badge/RTO-%E2%89%A445s-blue)
![RPO](https://img.shields.io/badge/RPO-0-green)
![Status](https://img.shields.io/badge/status-v1.0-brightgreen)
![License](https://img.shields.io/badge/license-Apache%202.0-blue)
![Docs](https://img.shields.io/badge/docs-bilingual%20EN%2FPL-yellow)

**Complete deployment guide for Oracle 19c Fast-Start Failover (FSFO) and Transparent Application Continuity (TAC) in a 3-site topology (MAA).**

---

## 📋 Target architecture

| Site | Role | Configuration |
|------|------|---------------|
| **DC**  | PRIMARY  | 2-node RAC, database `PRIM`, observer `obs_dc` (backup) |
| **DR**  | STANDBY  | 2-node RAC, database `STBY`, observer `obs_dr` (backup) |
| **EXT** | Observer | Master Observer `obs_ext` (no database; dedicated host) |

**Protection Mode:** MAX AVAILABILITY (SYNC DC↔DR, with SRL, AFFIRM)
**Failover Threshold:** 30 s | **Lag Limit:** 30 s | **Auto-Reinstate:** TRUE

---

## 📁 Project structure

```
20260423-FSFO-TAC-guide/
├── README.md                   # ← this file
├── LICENSE                     # Apache-2.0
├── .gitignore
├── checklist.html              # Interactive HTML checklist (Arch + 3 checklists + Timeline + Risk Matrix)
├── targets.lst                 # List of databases for validate_all.sh
│
├── docs/                       # Project documentation — 7 .md files
│   ├── DESIGN.md                       # Architecture, ADRs, compatibility, security
│   ├── PLAN.md                         # 6-phase plan, Weeks 1-13+
│   ├── FSFO-GUIDE.md                   # FSFO guide (11 sections)
│   ├── TAC-GUIDE.md                    # TAC guide (10 sections)
│   ├── INTEGRATION-GUIDE.md            # FSFO+TAC together (8 sections)
│   ├── FAILOVER-WALKTHROUGH.md         # Educational walkthrough (6 actors, 5 phases, t=0s→t=45s)
│   └── CODE-REVIEW-REPORT.md           # Sample review (82→97/100) — educational artifact
│
├── sql/                        # SQL scripts (run via sqlconn.sh) — 8 files
│   ├── fsfo_broker_status.sql        # Broker and FSFO status (5 sections)
│   ├── fsfo_check_readiness.sql      # FSFO pre-deployment readiness (6 sections)
│   ├── fsfo_configure_broker.sql     # dgmgrl command generator
│   ├── fsfo_monitor.sql              # Continuous FSFO+TAC monitoring (7 sections)
│   ├── tac_configure_service_rac.sql # TAC service configuration (srvctl + DBMS_SERVICE)
│   ├── tac_full_readiness.sql        # Full TAC readiness check (12 sections)
│   ├── tac_replay_monitor.sql        # TAC replay monitoring (6 sections)
│   └── validate_environment.sql      # 12 combined FSFO+TAC checks
│
├── bash/                       # Shell scripts — 4 files
│   ├── fsfo_setup.sh                 # FSFO setup orchestrator
│   ├── fsfo_monitor.sh               # Health monitor (cron-friendly, -a mode)
│   ├── tac_deploy.sh                 # TAC service deployment
│   └── validate_all.sh               # Full multi-DB validation
│
└── systemd/                    # systemd units for Observer HA — 3 files
    ├── dgmgrl-observer-dc.service
    ├── dgmgrl-observer-dr.service
    └── dgmgrl-observer-ext.service
```

---

## 🚀 Quick Reference

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

# Pre-deployment readiness check (TAC, 12 sections)
sqlconn.sh -s PRIM -f sql/tac_full_readiness.sql

# FSFO setup (dry-run)
bash/fsfo_setup.sh -s PRIM -d

# Health monitor (alert mode for cron)
bash/fsfo_monitor.sh -s PRIM -a

# TAC replay monitoring
sqlconn.sh -s PRIM -f sql/tac_replay_monitor.sql

# Multi-DB validation
bash/validate_all.sh -l targets.lst

# Interactive deployment checklist
# Open in a browser: checklist.html
```

---

## 📖 Where to start?

| Goal | Document |
|------|----------|
| Quick visualization of progress + Timeline + Risk Matrix | [Checklist (concept · 19c · 3-site)](https://krzysztof-i-cabaj.github.io/oracle-26ai-fsfo-tac-lab/checklist.html) |
| Architecture and decisions overview (ADRs) | [docs/DESIGN.md](docs/DESIGN.md) |
| Deployment schedule (6 phases, 13+ weeks) | [docs/PLAN.md](docs/PLAN.md) |
| Step-by-step FSFO deployment | [docs/FSFO-GUIDE.md](docs/FSFO-GUIDE.md) |
| TAC configuration (UCP, FAN, Transaction Guard) | [docs/TAC-GUIDE.md](docs/TAC-GUIDE.md) |
| End-to-end failover (FSFO→FAN→UCP→replay) | [docs/INTEGRATION-GUIDE.md](docs/INTEGRATION-GUIDE.md) |
| Educational failover-diagram walkthrough (6 actors, 5 phases) | [docs/FAILOVER-WALKTHROUGH.md](docs/FAILOVER-WALKTHROUGH.md) |
| Sample code review (82→97/100) — a critical-analysis process | [docs/CODE-REVIEW-REPORT.md](docs/CODE-REVIEW-REPORT.md) |

---

## ✅ Requirements

- Oracle Database **19c Enterprise Edition** on PRIM and STBY
- **SQLcl 25.2+** or **sqlplus** in `PATH`
- **sqlconn.sh** in `PATH` (from the `20260130-sqlconn` project) — every bash script invokes `sqlconn.sh` directly
- **Diagnostic Pack + Tuning Pack** (for ASH/AWR monitoring)
- A dedicated host for the **EXT** Observer (with `dgmgrl` and a wallet)
- **Java UCP 19c+** + **ojdbc11.jar** on the application side (for TAC)

---

## 🔒 Licensing

| Feature | License |
|---------|---------|
| Data Guard, DG Broker, FSFO, TAC | Built into **Enterprise Edition** |
| Active Data Guard (read-only standby) | Separate **ADG** option |
| UCP, FAN, Transaction Guard | No additional license |

Details in [docs/INTEGRATION-GUIDE.md § 8 Licensing Summary](docs/INTEGRATION-GUIDE.md#8-licensing-summary).

---

## 👤 Author

**KCB Kris**
Created: 2026-04-23
Version: 1.0

**Related:** [docs/FSFO-GUIDE.md](docs/FSFO-GUIDE.md) • [docs/TAC-GUIDE.md](docs/TAC-GUIDE.md) • [docs/INTEGRATION-GUIDE.md](docs/INTEGRATION-GUIDE.md) • [docs/PLAN.md](docs/PLAN.md) • [docs/DESIGN.md](docs/DESIGN.md)
