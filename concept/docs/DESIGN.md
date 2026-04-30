> 🇬🇧 English | [🇵🇱 Polski](./DESIGN_PL.md)

# 🎨 DESIGN.md — FSFO + TAC for Oracle 19c (3-site MAA)

![Oracle](https://img.shields.io/badge/Oracle-19c-F80000?logo=oracle&logoColor=white)
![Status](https://img.shields.io/badge/Status-accepted-4CAF50)
![ADR count](https://img.shields.io/badge/ADRs-8-4CAF50)

> Project specification — architectural decisions, conventions, security, testing.

---

## 📋 Table of Contents

1. [Context](#1-context)
2. [Architectural Decision Records (ADRs)](#2-architectural-decision-records-adrs)
3. [DB version compatibility](#3-db-version-compatibility)
4. [Naming conventions](#4-naming-conventions)
5. [Security](#5-security)
6. [Testing strategy](#6-testing-strategy)
7. [Alert thresholds](#7-alert-thresholds)
8. [Graceful degradation](#8-graceful-degradation)
9. [Future extensions](#9-future-extensions)
10. [Appendix](#10-appendix)

---

## 1. Context

### 1.1 Goal

Deliver a complete, repeatable set of documents and scripts for deploying Oracle 19c Fast-Start Failover (FSFO) + Transparent Application Continuity (TAC) in a 3-site MAA topology, with Observer HA distributed across DC, DR, and EXT sites.

### 1.2 Problem

Manual Data Guard failover + no transaction replay = long application downtime (minutes → tens of minutes), manual session-state recovery, transaction-loss risk during failure. A single Observer is a single point of failure in the FSFO decision chain.

### 1.3 Design principles

- **Zero-downtime target:** RTO ≤ 30 s, RPO = 0 (SYNC transport DC↔DR, MaxAvailability)
- **No application changes for TAC:** replay through UCP + Transaction Guard; the application is unaware of the failover
- **Observer HA by design:** always 3 observers in 3 sites (master on EXT, backups on DC/DR)
- **Dry-run first:** every state-changing script has a `-d` (dry-run) mode or generates a `.dgmgrl` script for DBA review
- **Tooling consolidation:** all bash scripts call the existing `sqlconn.sh` (from `PATH`) — no duplicated TNS/auth logic
- **EN/PL documentation:** every document, script header, and column alias is bilingual

### 1.4 Internal references

| File | Role |
|------|------|
| [README.md](../README.md) | Overview, file index, quickstart |
| [PLAN.md](PLAN.md) | 6-phase plan, Weeks 1-13+ |
| [FSFO-GUIDE.md](FSFO-GUIDE.md) | FSFO guide (11 sections) |
| [TAC-GUIDE.md](TAC-GUIDE.md) | TAC guide (10 sections) |
| [INTEGRATION-GUIDE.md](INTEGRATION-GUIDE.md) | FSFO+TAC integration (8 sections) |

---

## 2. Architectural Decision Records (ADRs)

### ADR registry

| ID | Title | Status | Date |
|----|-------|--------|------|
| ADR-001 | Master Observer on EXT (geographically separated) | accepted | 2026-04-23 |
| ADR-002 | Protection Mode = MAX AVAILABILITY (SYNC+AFFIRM) | accepted | 2026-04-23 |
| ADR-003 | FastStartFailoverThreshold = 30s, LagLimit = 30s | accepted | 2026-04-23 |
| ADR-004 | FastStartFailoverAutoReinstate = TRUE | accepted | 2026-04-23 |
| ADR-005 | TAC with failover_type=TRANSACTION and DYNAMIC session state | accepted | 2026-04-23 |
| ADR-006 | systemd units per site (instead of crontab/init.d) | accepted | 2026-04-23 |
| ADR-007 | Per-site Oracle Wallet for Observer credentials | accepted | 2026-04-23 |
| ADR-008 | Bash scripts call `sqlconn.sh` from `PATH` (no path) | accepted | 2026-04-23 |

---

### ADR-001: Master Observer on EXT (geographically separated)

- **Status:** accepted
- **Date:** 2026-04-23
- **Author:** KCB Kris

**Context:**
The Observer must be able to reliably arbitrate "split brain" between PRIM (DC) and STBY (DR). Placing it in either of those sites means that the failure of that site removes both the database and the Observer at the same time — there is no one to take the FSFO decision. A third-site Observer is the MAA recommendation.

**Decision:**
The Master Observer (`obs_ext`) runs in the EXT site (a dedicated host, no DG database). The `obs_dc` and `obs_dr` observers are backups in DC and DR, ready to take over the master role through FSFO observer HA.

**Consequences:**
- `+` No single site failure blocks the failover decision
- `+` DC↔DR network partitions do not cause "brain split" — EXT sees both sides
- `-` Requires a third location with network links to both sites (latency ≤ 50 ms preferred)
- `-` Operational cost: maintaining the observer host + wallet + systemd unit

**Rejected alternatives:**
- Observer only in DC (primary) — ruled out on a DC failure (single point of failure in the FSFO chain)
- Observer in DR — ruled out under "DC isolated, DR running, but Observer cannot see PRIM"
- External SaaS (Oracle Cloud Observer) — unacceptable for on-premise bank/fintech scenarios

---

### ADR-002: Protection Mode = MAX AVAILABILITY (SYNC+AFFIRM)

- **Status:** accepted
- **Date:** 2026-04-23
- **Author:** KCB Kris

**Context:**
FSFO needs immediate knowledge that the standby received every commit before failover — otherwise RPO > 0. MAX PROTECTION would be even safer, but it stops PRIM when STBY does not respond — unacceptable for OLTP applications.

**Decision:**
We use **MAX AVAILABILITY** with SYNC + AFFIRM transport, and Standby Redo Logs (SRL) on STBY. `FastStartFailoverLagLimit = 30 s` — when apply lag exceeds 30 s, FSFO cannot failover (to avoid losing data).

**Consequences:**
- `+` RPO = 0 under normal traffic (SYNC + AFFIRM)
- `+` On STBY trouble PRIM automatically degrades to MAX PERFORMANCE (async) and the application keeps running
- `-` Requires low DC↔DR network latency (an extra round-trip per commit) — acceptable for metro-area

**Rejected alternatives:**
- MAX PERFORMANCE (async) — RPO > 0, data may be lost
- MAX PROTECTION — stops production on STBY failure; unacceptable for 24/7 SLAs

---

### ADR-003: FastStartFailoverThreshold = 30 s, LagLimit = 30 s

- **Status:** accepted
- **Date:** 2026-04-23
- **Author:** KCB Kris

**Context:**
The threshold determines how long the Observer waits after a heartbeat loss before initiating FSFO. Too short = false positives (failover on network flaps), too long = a longer RTO. LagLimit determines the maximum apply lag at which FSFO is allowed.

**Decision:**
`FastStartFailoverThreshold = 30` (s), `FastStartFailoverLagLimit = 30` (s). Together with FAN/UCP reaction this gives an end-to-end RTO of ~30–45 s.

**Consequences:**
- `+` Robust against short-lived network flaps (< 30 s)
- `+` Apply lag ≤ 30 s = RPO acceptable for fintech
- `-` RTO ~30 s — insufficient for ultra-low-latency HFT; acceptable for retail/corporate banking

**Rejected alternatives:**
- Threshold = 10 s — MAA 2024 benchmarks showed too many false positives
- Threshold = 60 s — doubles the RTO; unacceptable for 99.995% SLAs

---

### ADR-004: FastStartFailoverAutoReinstate = TRUE

- **Status:** accepted
- **Date:** 2026-04-23
- **Author:** KCB Kris

**Context:**
After a failover the "old primary" must be brought back as the new standby. This can be done manually (DBA `REINSTATE DATABASE`) or automatically.

**Decision:**
`AutoReinstate = TRUE`. When the old primary is reachable again, the Broker automatically reinstates it (requires Flashback Database ON).

**Consequences:**
- `+` Self-healing after transient failures (network, reboot)
- `+` Lower on-call DBA load
- `-` Requires `FLASHBACK ON` + an adequately sized FRA (Fast Recovery Area)
- `-` May reinstate at unexpected times — the alert log must be monitored

**Rejected alternatives:**
- AutoReinstate = FALSE — every failure requires manual DBA intervention; raises MTTR

---

### ADR-005: TAC with failover_type=TRANSACTION and DYNAMIC session state

- **Status:** accepted
- **Date:** 2026-04-23
- **Author:** KCB Kris

**Context:**
TAC has three settings that matter for replay: `failover_type`, `session_state_consistency`, `commit_outcome`. The defaults (`SELECT`, `STATIC`) do not support transaction replay.

**Decision:**
```
failover_type             = TRANSACTION
session_state_consistency = DYNAMIC
commit_outcome            = TRUE
retention_timeout         = 86400 (24 h)
replay_initiation_timeout = 900
drain_timeout             = 300
```

**Consequences:**
- `+` Full replay of in-flight transactions after failover
- `+` Session state preserved (NLS, PL/SQL package vars, temp tables)
- `-` The application must use UCP (HikariCP does not fully support TAC)
- `-` 24-hour outcome retention loads up the `SYS.LTXID_TRANS$` table — monitor its size

**Rejected alternatives:**
- `failover_type=SELECT` (legacy TAF) — no DML replay
- `session_state_consistency=STATIC` — loses PL/SQL state during replay

---

### ADR-006: systemd units per site (instead of crontab/init.d)

- **Status:** accepted
- **Date:** 2026-04-23
- **Author:** KCB Kris

**Context:**
The Observer must run as a long-running background process on each of the 3 hosts (DC, DR, EXT). Requirements: automatic restart after a crash, dependency on the network, logging to journald, control via `systemctl`.

**Decision:**
A per-site systemd unit file with `Restart=on-failure`, `After=network-online.target`, user `oracle`, and a wallet path specific to the site. Files in [systemd/](../systemd/), deployment in [FSFO-GUIDE § 6.7](FSFO-GUIDE.md#67-observer-ha---systemd-units).

**Consequences:**
- `+` Standard OS tooling (`systemctl status/start/stop/restart`)
- `+` Automatic restart after the observer crashes
- `+` journald integration (`journalctl -u dgmgrl-observer-ext`)
- `-` Requires systemd (does not run on legacy RHEL 6) — RHEL/OL 7+ required

**Rejected alternatives:**
- Crontab `@reboot dgmgrl ... &` — no auto-restart after a crash, no logging
- init.d SysV — deprecated in RHEL 7+
- supervisord — extra dependency

---

### ADR-007: Per-site Oracle Wallet for Observer credentials

- **Status:** accepted
- **Date:** 2026-04-23
- **Author:** KCB Kris

**Context:**
The Observer connects to PRIM and STBY as `sys` (DBA) — its password cannot live in a systemd file or a bash script. Oracle Wallet + a TNS alias is the recommended approach.

**Decision:**
Each of the 3 observers has its own Oracle Wallet in `/etc/oracle/wallet/observer-{hh,oe,ext}` containing credentials for `@PRIM_ADMIN` and `@STBY_ADMIN`. Access: `chmod 600`, owner `oracle:oinstall`. The wallet **never goes into the repository**.

**Consequences:**
- `+` Zero plaintext passwords
- `+` Password rotation through `mkstore -modifyCredential`, no observer restart needed
- `+` Compatible with `dgmgrl /@PRIM_ADMIN` (no password on the CLI)
- `-` Separate wallets on the 3 hosts — deployment procedure in [FSFO-GUIDE § 6.8](FSFO-GUIDE.md#68-observer-wallet-per-site)

**Rejected alternatives:**
- Plaintext passwords in the systemd unit — violates global security rules (`../CLAUDE.md`)
- Single shared wallet on NFS — single point of failure + compromises every observer at once
- OS-level keyring — does not integrate with `dgmgrl`

---

### ADR-008: Bash scripts call `sqlconn.sh` from `PATH` (no path)

- **Status:** accepted
- **Date:** 2026-04-23
- **Author:** KCB Kris

**Context:**
A mature `sqlconn.sh` already exists (from [../20260130-sqlconn/](../../20260130-sqlconn/)) handling HA, A/B failover, technical/named accounts, dry-run, C## fallback. Duplicating this logic in the FSFO scripts would be unhealthy redundancy.

**Decision:**
The scripts [bash/fsfo_setup.sh](../bash/fsfo_setup.sh), [bash/fsfo_monitor.sh](../bash/fsfo_monitor.sh), [bash/tac_deploy.sh](../bash/tac_deploy.sh), [bash/validate_all.sh](../bash/validate_all.sh) call `sqlconn.sh` **directly** — without a path (it is on `PATH` on the target hosts). We do not `source` it, we invoke it as a subprocess.

**Consequences:**
- `+` No duplicated TNS / auth / HA logic
- `+` Consistent logging (the same log format, the same wallet/credential store)
- `+` Updates to `sqlconn.sh` automatically propagate to the FSFO toolkit
- `-` Portability: on a host without `sqlconn.sh` the scripts will not run — this is a prerequisite called out in README and `usage()`

**Rejected alternatives:**
- Standalone sqlplus in every script — duplication, configuration drift
- A symbolic link to `sqlconn.sh` inside the project directory — makes upgrades harder
- Copying `sqlconn.sh` — old code lingers in two places

---

## 3. DB version compatibility

### 3.1 Supported versions

| Version | Status | Notes |
|---------|--------|-------|
| Oracle 12c | not supported | FSFO 12c is supported, but TAC (19c+) is not |
| Oracle 19c | **primary target** | FSFO + TAC fully functional, the project's main target |
| Oracle 21c | compatible | Works unchanged; 21c only adds minor tuning knobs |
| Oracle 23ai | compatible with caveats | TAC still works; new features (True Cache) not used |
| Oracle 26ai | compatible | On-premise; AI Vector Search does not touch FSFO/TAC |

### 3.2 Architecture

| Aspect | Value |
|--------|-------|
| CDB / Non-CDB | CDB required for 19c+ (Non-CDB deprecated) |
| RAC | **required** — PRIM and STBY are 2-node RAC |
| Data Guard | **required** — Physical Standby, DG Broker |
| Multitenant (PDB) | supported — TAC per-service per-PDB |
| Exadata | supported — redo apply optimization is even faster |

### 3.3 System view differences

| View | 19c | 21c | 23ai | Notes |
|------|-----|-----|------|-------|
| `V$DATAGUARD_STATS` | ✓ | ✓ | ✓ | Core for FSFO monitoring |
| `GV$REPLAY_STAT_SUMMARY` | ✓ | ✓ | ✓ | Core for TAC monitoring |
| `DBA_DG_BROKER_CONFIG_PROPERTIES` | ✓ | ✓ | ✓ | Broker properties since 19c |
| `DBMS_APP_CONT` | ✓ | ✓ | ✓ | Transaction Guard package |
| `V$FS_FAILOVER_STATS` | ✓ | ✓ | ✓ | FSFO statistics |

### 3.4 Strategy for handling differences

- **Conditional compilation** (`$IF DBMS_DB_VERSION.VERSION >= 19 $THEN`): used in `validate_environment.sql` for graceful degradation on 12c (the readiness check returns FAIL with an explicit message)
- **Separate per-version files:** no — we maintain a single set targeting 19c+
- **Dynamic SQL:** only in the dgmgrl generator (`fsfo_configure_broker.sql`) for parameterising database names

---

## 4. Naming conventions

### 4.1 Files

| Type | Convention | Example |
|------|------------|---------|
| SQL readiness | `fsfo_*_readiness.sql` / `validate_*.sql` | `fsfo_check_readiness.sql` |
| SQL status | `fsfo_*_status.sql` / `*_monitor.sql` | `fsfo_broker_status.sql` |
| SQL generator | `fsfo_configure_*.sql` | `fsfo_configure_broker.sql` |
| SQL service | `tac_configure_service_*.sql` | `tac_configure_service_rac.sql` |
| Bash orchestrator | `{feature}_setup.sh` | `fsfo_setup.sh` |
| Bash monitor | `{feature}_monitor.sh` | `fsfo_monitor.sh` |
| Bash multi-DB | `validate_all.sh` | — |
| systemd unit | `dgmgrl-observer-{site}.service` | `dgmgrl-observer-ext.service` |
| Output log | `./logs/fsfo_{YYYYMMDD_HHMMSS}.log` | `./logs/fsfo_20260420_143022.log` |
| Output report | `./reports/{db}_fsfo_{YYYYMMDD_HHMM}.txt` | `./reports/PRIM_fsfo_20260420_1430.txt` |

### 4.2 Database objects

| Object | Convention | Example |
|--------|------------|---------|
| DG databases | 4 characters, uppercase | `PRIM`, `STBY` |
| Observer name | `obs_{site_lower}` | `obs_dc`, `obs_dr`, `obs_ext` |
| TAC service | `{APP}_TAC` (RW), `{APP}_RO` (standby read-only) | `MYAPP_TAC`, `MYAPP_RO` |
| Primary TNS alias | `{DB}_ADMIN` (in wallet) | `PRIM_ADMIN` |
| Static listener | `{DB}_DGMGRL` | `PRIM_DGMGRL`, `STBY_DGMGRL` |

### 4.3 SQL*Plus variables

- Parameterise via `ACCEPT ... PROMPT ... DEFAULT ...` (interactive)
- Or `DEFINE` at the top of the script (for non-interactive runs)
- **Never** bash-style `${var}` in `.sql`
- Result-set columns: aliases in **Polish** (per `../_oracle_/CLAUDE.md`)

### 4.4 Host sanitisation

| Source | Rule | Example |
|--------|------|---------|
| `ora-PRIM-a` | unchanged — used inside `sqlconn.sh` | — |
| `obs-ext.corp.local` | `.` → `_` in output filenames | `obs-ext_corp_local.log` |

---

## 5. Security

### 5.1 Credential management

- **Observer:** per-site Oracle Wallet (ADR-007)
- **Monitoring DBA:** SQLcl JCEKS credential store (per workspace convention `../_oracle_/CLAUDE.md`)
- **Application TAC user:** Oracle Wallet or a secrets manager (AWS/Azure/HashiCorp)

**Rules:**
- Credentials **never** end up in the repository (FSFO wallets, JCEKS, `.env` in `.gitignore`)
- `.db_secrets`, `.env` files: `chmod 600`
- `tnsnames.ora` **without passwords** — passwords only in the wallet/JCEKS
- The Observer connects as `sys` — use only via the wallet with TNS aliases `PRIM_ADMIN` / `STBY_ADMIN`

### 5.2 Least privilege

| Role | Privileges | Usage |
|------|------------|-------|
| `ops_monitor` (technical) | SELECT_CATALOG_ROLE | Read-only scripts (`fsfo_broker_status.sql`, `fsfo_monitor.sql`) |
| `C##dba_kris` (named) | SYSDBA | State-changing scripts (`fsfo_configure_broker.sql`) |
| `observer` (wallet) | SYSDG | Observer process — least privilege for FSFO decision-making |
| `appuser_tac` (application) | CREATE SESSION + app role | Production UCP pool |

**SYSDG vs SYSDBA:** the Observer should use SYSDG (a dedicated DG role introduced in 12.2) instead of SYSDBA — smaller attack surface.

### 5.3 PDB / CDB safety

- FSFO operates at the CDB level (the whole database fails over atomically)
- TAC services are configured per-PDB (role-based: `service -role PRIMARY` + `service -role PHYSICAL_STANDBY`)
- For multi-PDB environments — iterate over `DBA_PDBS` when configuring TAC

### 5.4 Licensing

**Key license packages:**
- **Enterprise Edition (EE)** — required (Data Guard, FSFO, TAC are built-in)
- **Active Data Guard (option)** — optional; required for read-only standby with real-time apply or fast incremental backups on the standby
- **Diagnostic Pack + Tuning Pack** — for `V$ACTIVE_SESSION_HISTORY`, AWR, SQL Tuning Advisor (used in `fsfo_monitor.sql` section 7)
- **Real Application Clusters (RAC)** — for the 2-node RAC in DC and DR

**The project uses:** EE + RAC + Diagnostic Pack + Tuning Pack. ADG **not required** in the core scenario (only if you want a read-only offload on STBY — then ADR-009 should be added).

### 5.5 Network

- **Required ports:** 1521 (SQL*Net), 6200 (cross-site ONS for FAN), 1522 (DGMGRL static listener)
- **Firewall matrix** in [TAC-GUIDE § 6.4](TAC-GUIDE.md#64-firewall-rules--reguły-firewalla)
- **Cross-site ONS:** PRIM ONS ↔ STBY ONS must see each other after a switchover
- **Observer → PRIM/STBY:** port 1521 (SQL*Net for dgmgrl heartbeats)

---

## 6. Testing strategy

### 6.1 Dry-run pattern

Per the global `../CLAUDE.md`:

- **SQL (state change):** the 3-step pattern
  ```
  -- KROK 1 / STEP 1: Preview (SELECT — safe)
  -- KROK 2 / STEP 2: Actual change
  -- KROK 3 / STEP 3: Verification
  ```
- **Bash:** the `-d` (dry-run) flag only prints commands without running them
- **dgmgrl generator:** `fsfo_configure_broker.sql` emits a `.dgmgrl` file for review, it does not execute

### 6.2 Smoke test

```bash
# 1. bash syntax check
for f in bash/*.sh; do bash -n "$f" && echo "OK: $f" || echo "FAIL: $f"; done

# 2. SQL syntax check (dry parse in sqlcl)
for f in sql/*.sql; do echo "@@$f" | sqlcl -nolog -S | grep -i 'error' && echo "FAIL: $f"; done

# 3. Orchestrator dry-run
bash/fsfo_setup.sh -s PRIM -d

# 4. Monitor in alert mode (offline — without a database returns exit 2)
bash/fsfo_monitor.sh -s PRIM -a
```

### 6.3 Test matrix

| Scenario | 19c | 21c | 23ai | Single | RAC | DG |
|----------|-----|-----|------|--------|-----|----|
| Smoke test (sql syntax + bash -n) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Readiness check | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Broker configure (dry-run) | ✓ | ✓ | ✓ | — | ✓ | ✓ |
| Planned switchover | ✓ | ✓ | ✓ | — | ✓ | ✓ |
| Simulated PRIM crash | ✓ | ✓ | ✓ | — | ✓ | ✓ |
| Observer HA failover (master ↓) | ✓ | ✓ | ✓ | — | ✓ | ✓ |
| TAC replay test (SHUTDOWN ABORT node 1) | ✓ | ✓ | ✓ | — | ✓ | ✓ |
| Reinstate (AutoReinstate) | ✓ | ✓ | ✓ | — | ✓ | ✓ |
| Rolling patch with FSFO active | ✓ | ✓ | ✓ | — | ✓ | ✓ |

### 6.4 Rollback plan

- **Broker config error:** `REMOVE CONFIGURATION [PRESERVE DESTINATIONS]` — reverts the state to before the broker was enabled; the standby is configured manually by the DBA
- **FSFO error:** `DISABLE FAST_START FAILOVER` — the Observer stops deciding; switchover is manual only
- **TAC error (service):** `srvctl modify service` with `-failovertype NONE` — disables TAC; the application keeps running without replay (no zero-downtime)
- **Observer error:** `systemctl stop dgmgrl-observer-ext` + manual `DISABLE FAST_START FAILOVER` if all 3 observers are down

---

## 7. Alert thresholds

### 7.1 Broker status

| Value | Pill | Rationale |
|-------|------|-----------|
| `SUCCESS` | ✅ OK | Broker healthy, all DBs in sync |
| `WARNING` | 🟡 WARN | Apply lag > 0 but < 30 s — monitor; no immediate action |
| `ORA-16819`, `ORA-16820`, `ORA-16825` | 🔴 CRIT | Configuration errors; see [FSFO-GUIDE § 10](FSFO-GUIDE.md#10-troubleshooting) |

### 7.2 FSFO status

| Value | Pill | Rationale |
|-------|------|-----------|
| `ENABLED` + Observer connected | ✅ OK | FSFO ready; auto-failover active |
| `ENABLED` + Observer disconnected > 60 s | 🟡 WARN | Observer HA should take over; check the alert log |
| `DISABLED` | 🔴 CRIT | No auto-failover — only manual switchover available |

### 7.3 Apply lag (FastStartFailoverLagLimit = 30 s)

| Value | Pill | Rationale |
|-------|------|-----------|
| `lag < 5 s` | ✅ OK | Normal load |
| `5 s ≤ lag < 30 s` | 🟡 WARN | Standby behind; monitor; FSFO still available |
| `lag ≥ 30 s` | 🔴 CRIT | FSFO **unavailable** (LagLimit exceeded) — zero-downtime not guaranteed |

### 7.4 TAC replay success rate

| Value | Pill | Rationale |
|-------|------|-----------|
| `success_pct ≥ 95%` | ✅ OK | Healthy — mutable objects and session state managed correctly |
| `80% ≤ success_pct < 95%` | 🟡 WARN | Some transactions do not replay — check `GV$REPLAY_STAT_SUMMARY.requests_failed` |
| `success_pct < 80%` | 🔴 CRIT | Application-design issue — likely non-replayable operations (DDL, external calls) |

### 7.5 Observer heartbeat

| Value | Pill | Rationale |
|-------|------|-----------|
| `last_ping < 10 s` | ✅ OK | Observer alive |
| `10 s ≤ last_ping < 60 s` | 🟡 WARN | Network latency or GC pause |
| `last_ping ≥ 60 s` | 🔴 CRIT | The Observer probably died; the backup should take over |

---

## 8. Graceful degradation

### 8.1 Availability matrix

| Component | Required? | Without it |
|-----------|-----------|------------|
| Enterprise Edition | **YES** | FSFO/TAC are not available — the project does not work |
| RAC | YES (per assumption) | FSFO works on Single Instance, but the project targets RAC 2-node |
| Data Guard + SRL | **YES** | FSFO has nothing to fail over to |
| DG Broker | **YES** | Without the broker only manual switchover |
| `FLASHBACK ON` | YES (for AutoReinstate) | AutoReinstate=FALSE; manual reinstate required after every failover |
| `FORCE_LOGGING` | **YES** | The standby may diverge from the primary |
| Diagnostic Pack | NO | `fsfo_monitor.sql` section 7 (ASH/AWR) — graceful degradation to V$SESSION |
| Tuning Pack | NO | No SQL recommendations; the rest works |
| Active Data Guard (option) | NO | Read-only standby unavailable; FSFO still works |
| UCP on the client | YES (for TAC) | Without UCP — no replay; the application sees ORA-03113 |
| FAN/ONS | YES (for TAC) | UCP gets no events → no fast connection failover |

### 8.2 Fallback patterns

**Without Diagnostic Pack (ASH/AWR license):**

```sql
-- Standard (Diagnostic Pack required):
SELECT COUNT(*) FROM V$ACTIVE_SESSION_HISTORY
WHERE sample_time > SYSDATE - 5/1440;

-- Fallback (without the license):
SELECT COUNT(*) FROM V$SESSION
WHERE status = 'ACTIVE' AND type = 'USER';
```

In `fsfo_monitor.sql` — section 7 wrapped in an `$IF` conditional:

```sql
$IF (SELECT value FROM v$option WHERE parameter = 'Diagnostic Pack') = 'TRUE' $THEN
   -- Use ASH
$ELSIF
   -- Use V$SESSION sampling
$END
```

**Without an Observer (all 3 down):**
- FSFO stays `ENABLED` but no one can take the decision
- Manual failover by the DBA: [INTEGRATION-GUIDE § 6.2](INTEGRATION-GUIDE.md#62-emergency-failover-manual)

**Without FAN/ONS (cross-site ONS blocked by firewall):**
- UCP receives no DOWN/UP events
- The application sees ORA-03113; JDBC reconnects via `(FAILOVER=ON)` in TNS
- RTO grows from ~30 s to about a minute (TCP timeout)

---

## 9. Future extensions

### 9.1 Planned (backlog)

| Feature | Complexity | Description |
|---------|------------|-------------|
| ADG (Active Data Guard) integration | medium | Read-only offload to STBY for reporting/analytics |
| Grafana dashboard | medium | Visualizing `V$DATAGUARD_STATS` + `GV$REPLAY_STAT_SUMMARY` |
| Automated failover drill | high | Quarterly failover test + audit report |
| Multi-standby (cascade) | high | Additional standby in a third DC for regional DR |
| Oracle 23ai True Cache integration | high | A read-only cache layer with its own failover |

### 9.2 Deliberately skipped

| Feature | Reason for skipping |
|---------|---------------------|
| MAX PROTECTION mode | Stops production when STBY does not respond; unacceptable for 24/7 SLA |
| Async transport (MAX PERFORMANCE) | RPO > 0; does not meet fintech requirements |
| HikariCP instead of UCP | HikariCP does not fully support TAC (no LTXID outcome query) |
| Oracle Cloud Observer | On-premise only — security compliance |
| Zero-data-loss (ZDLRA) | A separate project, out of scope for FSFO+TAC |
| Observer without systemd (crontab) | No auto-restart after a crash; rejected in ADR-006 |

---

## 10. Appendix

### 10.1 External references

- [Oracle Database 19c Data Guard Concepts and Administration](https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/) — DG reference
- [Oracle Database 19c Data Guard Broker](https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/) — Broker + FSFO reference
- [Oracle MAA Best Practices](https://www.oracle.com/database/technologies/high-availability/maa.html) — reference architecture
- [Transparent Application Continuity Technical Brief](https://www.oracle.com/a/tech/docs/tac-technical-brief.pdf) — TAC whitepaper
- [Oracle Note 2064122.1 (MOS)](https://support.oracle.com) — FSFO Observer troubleshooting
- [UCP Developer's Guide 19c](https://docs.oracle.com/en/database/oracle/oracle-database/19/jjucp/) — pool configuration

### 10.2 Glossary

| Term | Definition |
|------|------------|
| **FSFO** | Fast-Start Failover — automatic primary→standby promotion driven by the Observer |
| **TAC** | Transparent Application Continuity — replay of in-flight transactions in 19c+ (successor of AC) |
| **AC** | Application Continuity — older replay version (12c) that required application changes |
| **Observer** | A `dgmgrl` process monitoring PRIM/STBY and initiating FSFO |
| **Broker** | Data Guard Broker — DG management framework via `dgmgrl` / `DBMS_DG` |
| **dgmgrl** | Data Guard Manager CLI — the command for broker management |
| **MAA** | Maximum Availability Architecture — Oracle's HA reference architecture |
| **SRL** | Standby Redo Logs — required for real-time apply and FSFO |
| **FAN** | Fast Application Notification — event system publishing state changes |
| **ONS** | Oracle Notification Service — the FAN transport (port 6200) |
| **UCP** | Universal Connection Pool — Oracle Java connection pool with TAC support |
| **TG** | Transaction Guard — the LTXID-based safe-replay mechanism |
| **LTXID** | Logical Transaction ID — the transaction identifier for TG |
| **SYSDG** | System privilege for Data Guard operations (12.2+) |
| **ADG** | Active Data Guard — license option for a read-only standby with real-time apply |
| **RTO** | Recovery Time Objective — maximum acceptable recovery time |
| **RPO** | Recovery Point Objective — maximum acceptable data loss |

---

## 👤 Author

- **KCB Kris** — author and project maintainer
- Date: 2026-04-23
- Version: 1.0
