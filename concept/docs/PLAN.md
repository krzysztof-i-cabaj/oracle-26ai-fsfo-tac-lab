> 🇬🇧 English | [🇵🇱 Polski](./PLAN_PL.md)

# 📅 PLAN.md — FSFO + TAC Oracle 19c deployment plan

![Status](https://img.shields.io/badge/Status-ready-4CAF50)
![Duration](https://img.shields.io/badge/Duration-13%2B%20weeks-blue)
![Phases](https://img.shields.io/badge/Phases-6-orange)

> Deployment timeline for Oracle 19c FSFO + TAC in a 3-site topology (DC/DR/EXT).

> **💡 Interactive version:** [checklist.html](../checklist.html) contains the same plan in graphical form (Gantt timeline, risk matrix, click-able checkboxes with progress saved in `localStorage`).

---

## 🎯 Project goals

| Goal | Success metric |
|------|----------------|
| RTO ≤ 30 s on PRIM failure | End-to-end failover test ≤ 30 s |
| RPO = 0 | SYNC+AFFIRM transport, zero lost transactions in tests |
| Zero application changes for TAC | Application compiles without `-D` flags, pool is UCP-only |
| Observer HA without SPOF | 3 observers (DC/DR/EXT); any single one may fail with no impact |
| Self-healing after transient failure | `AutoReinstate=TRUE` — old primary returns as standby with no DBA action |

---

## 📊 Timeline (Gantt-style)

```
                      Week  1  2  3  4  5  6  7  8  9 10 11 12 13 14+
Phase 0 — Diagnostics  ██
Phase 1 — DG Broker       ██ ██
Phase 2 — FSFO + Observer       ██ ██
Phase 3 — TAC Service                 ██
Phase 4 — UCP + FAN                      ██ ██ ██
Phase 5 — Integration Testing                     ██ ██ ██ ██
Phase 6 — Go-Live + Monitoring                                   ████...
```

---

## 📋 Phase 0 — Diagnostics (Week 1)

**Goal:** Establish an environment baseline, document the current state, and identify gaps before deployment.

### Tasks

| # | Task | Tool | Output |
|---|------|------|--------|
| 0.1 | Audit Oracle versions on both clusters (DC, DR) | `sqlconn.sh -s PRIM -f sql/fsfo_check_readiness.sql` | `reports/PRIM_readiness.txt` |
| 0.2 | Audit force_logging, flashback, SRL, broker | Sections 1-4 of `fsfo_check_readiness.sql` | as above |
| 0.3 | Verify licensing (EE, Diagnostic, Tuning) | `SELECT * FROM v$option` | Report into DESIGN § 5.4 |
| 0.4 | Map the DC↔DR↔EXT network (latency, MTU, firewall) | `ping`, `mtr`, `iperf3` | Network report |
| 0.5 | Check ports: 1521, 1522 (DGMGRL static), 6200 (ONS) | `netstat -tlnp`, `nmap` | List of blocks to escalate |
| 0.6 | Prepare 3 observer hosts (DC/DR/EXT) — OS, dgmgrl, systemd | Manual | Hosts ready |
| 0.7 | Review CLAUDE.md + DESIGN.md with the team | Meeting | DBA lead sign-off |

### Deliverables

- Readiness report for PRIM and STBY
- Sign-off from DBA, Network, and Security teams
- Updated DESIGN.md (the "future decisions" section filled in based on facts)

### Gate to Phase 1

- [ ] PRIM and STBY: Oracle 19c EE + RAC
- [ ] Force logging ON, Flashback ON on both
- [ ] SRL configured on STBY (N+1 logs, size = primary redo)
- [ ] Ports open in every direction (DC↔DR, DC↔EXT, DR↔EXT)
- [ ] 3 observer hosts available (CPU, RAM, disk, network)

---

## 📋 Phase 1 — DG Broker setup (Weeks 2-3)

**Goal:** Enable and configure the Data Guard Broker on PRIM and STBY, then verify a manual switchover.

### Tasks

| # | Task | Command | Where |
|---|------|---------|-------|
| 1.1 | Set `dg_broker_start=TRUE` on both DBs | `ALTER SYSTEM SET dg_broker_start=TRUE SCOPE=BOTH SID='*';` | PRIM + STBY |
| 1.2 | Configure a static listener in `listener.ora` (SIDs `PRIM_DGMGRL`, `STBY_DGMGRL`) | Edit `listener.ora` + `lsnrctl reload` | All RAC nodes |
| 1.3 | Generate the dgmgrl script via the generator | `sqlconn.sh -s PRIM -f sql/fsfo_configure_broker.sql -o broker_setup.dgmgrl` | DBA laptop |
| 1.4 | DBA-lead review of `broker_setup.dgmgrl` | Manual | — |
| 1.5 | `CREATE CONFIGURATION`, `ADD DATABASE`, `ENABLE CONFIGURATION` | `dgmgrl sys/@PRIM_ADMIN @broker_setup.dgmgrl` | PRIM (primary) |
| 1.6 | Verify: `SHOW CONFIGURATION` — SUCCESS | dgmgrl | — |
| 1.7 | Test manual switchover PRIM → STBY | `SWITCHOVER TO STBY;` | — |
| 1.8 | Switchback STBY → PRIM | `SWITCHOVER TO PRIM;` | — |
| 1.9 | Monitoring `fsfo_broker_status.sql` | `sqlconn.sh -s PRIM -f sql/fsfo_broker_status.sql` | — |

### Deliverables

- Broker configuration `DG_CONFIG_PRIM_STBY` in `SUCCESS` state
- Successful manual switchover test (round-trip PRIM → STBY → PRIM)
- Switchover log (apply lag = 0, transport lag = 0 after returning)

### Gate to Phase 2

- [ ] `SHOW CONFIGURATION` returns `SUCCESS`
- [ ] `SHOW DATABASE PRIM` / `SHOW DATABASE STBY` — both `SUCCESS`
- [ ] Manual switchover: completed, round-trip ≤ 2 minutes
- [ ] `DBA_DG_BROKER_CONFIG.ACTIVE` = `TRUE` on both

---

## 📋 Phase 2 — FSFO + Observer (Weeks 4-5)

**Goal:** Enable FSFO, deploy 3 Observers (DC/DR/EXT), and verify auto-failover.

### Tasks

| # | Task | Command | Where |
|---|------|---------|-------|
| 2.1 | Set FSFO properties | dgmgrl `EDIT CONFIGURATION SET PROPERTY ...` | PRIM |
| 2.2 | FastStartFailoverThreshold=30, LagLimit=30, AutoReinstate=TRUE, ObserverOverride=TRUE, ObserverReconnect=10 | see [FSFO-GUIDE § 5](FSFO-GUIDE.md#5-fsfo-configuration) | — |
| 2.3 | Create Observer wallets on the 3 hosts (DC/DR/EXT) | `mkstore -wrl /etc/oracle/wallet/observer-{dc,dr,ext} -createCredential ...` | 3 hosts |
| 2.4 | Deploy systemd unit files (from [systemd/](../systemd/)) | `cp systemd/dgmgrl-observer-{dc,dr,ext}.service /etc/systemd/system/; systemctl daemon-reload` | 3 hosts |
| 2.5 | `ADD OBSERVER 'obs_dc' ON 'host-dc'` (and the same for DR, EXT) | dgmgrl | PRIM |
| 2.6 | `SET MASTEROBSERVER TO obs_ext` | dgmgrl | PRIM |
| 2.7 | `ENABLE FAST_START FAILOVER` | dgmgrl | PRIM |
| 2.8 | `systemctl start dgmgrl-observer-ext` (master), then the backups | systemctl | 3 hosts |
| 2.9 | Verify `SHOW OBSERVER` — all `YES` connected | dgmgrl | — |
| 2.10 | **Auto-failover test:** `SHUTDOWN ABORT` on PRIM | — | PRIM |
| 2.11 | Expected: FSFO switches to STBY in ~30-45 s | Monitor `fsfo_monitor.sh -s STBY -a` | — |
| 2.12 | Reinstate test: `startup mount` on the old PRIM | Auto: broker performs reinstate | — |
| 2.13 | Switchback to the original role | `SWITCHOVER TO PRIM;` | — |
| 2.14 | **Observer HA test:** kill the master (`systemctl stop`) → backup should take over | — | obs_ext |

### Deliverables

- FSFO `ENABLED` + 3 Observers connected
- Successful auto-failover test (RTO ≤ 45 s)
- Successful auto-reinstate test
- Successful Observer HA test (master failover ≤ 10 s)

### Gate to Phase 3

- [ ] `SHOW FAST_START FAILOVER` returns `ENABLED` + `Master Observer: obs_ext`
- [ ] All 3 observers `YES Connected`
- [ ] Auto-failover test passed (RTO documented)
- [ ] Auto-reinstate after failover — works
- [ ] Observer master failover — works (< 60 s quorum re-establishment)

---

## 📋 Phase 3 — TAC service configuration (Week 6)

**Goal:** Configure TAC-enabled services on PRIM and STBY and verify their service-level attributes.

### Tasks

| # | Task | Command | Where |
|---|------|---------|-------|
| 3.1 | Review `sql/tac_configure_service_rac.sql` | Manual | — |
| 3.2 | Run on PRIM (dry-run) | `sqlconn.sh -s PRIM -i -f sql/tac_configure_service_rac.sql -d` | PRIM |
| 3.3 | Actual run (`srvctl add service` for MYAPP_TAC, role=PRIMARY) | `bash/tac_deploy.sh -s PRIM` | PRIM |
| 3.4 | Create MYAPP_RO (role=PHYSICAL_STANDBY) | as above | — |
| 3.5 | Verify attributes: `srvctl config service -d PRIM -s MYAPP_TAC` | — | — |
| 3.6 | `failover_type=TRANSACTION`, `commit_outcome=TRUE`, `session_state_consistency=DYNAMIC` — all confirmed | `SELECT * FROM dba_services WHERE name = 'MYAPP_TAC';` | PRIM |
| 3.7 | Start service: `srvctl start service -d PRIM -s MYAPP_TAC` | — | PRIM |
| 3.8 | Confirm the service runs on both RAC instances | `srvctl status service -d PRIM -s MYAPP_TAC` | PRIM |
| 3.9 | Switchover test: the service should follow STBY | `SWITCHOVER TO STBY;` + `srvctl status` | — |
| 3.10 | Switchback | — | — |

### Deliverables

- TAC services MYAPP_TAC and MYAPP_RO running on both clusters
- Role-based service (auto-start on the PRIMARY role after a switchover)
- Service attributes match [ADR-005](DESIGN.md#adr-005-tac-z-failover_typetransaction-i-dynamic-session-state)

### Gate to Phase 4

- [ ] `MYAPP_TAC` + `MYAPP_RO` running
- [ ] `failover_type=TRANSACTION` confirmed in `dba_services`
- [ ] Service auto-switches role on switchover
- [ ] `commit_outcome=TRUE`, `drain_timeout=300`

---

## 📋 Phase 4 — UCP + FAN configuration (Weeks 7-9)

**Goal:** Configure the application (UCP pool), enable cross-site FAN, and run end-to-end TAC tests on developer machines.

### Tasks

| # | Task | Owner | Week |
|---|------|-------|------|
| 4.1 | Upgrade JDBC to 19c+ (`ojdbc11.jar`) in the application repo | App team | W7 |
| 4.2 | Add `oracle-ucp.jar` and `ons.jar` to dependencies | App team | W7 |
| 4.3 | Refactor pool: Hikari/DBCP → UCP | App team | W7-W8 |
| 4.4 | `ConnectionFactoryClassName=oracle.jdbc.replay.OracleDataSourceImpl` | App team | W8 |
| 4.5 | TNS string with two ADDRESS_LISTs (DC+DR) and `FAILOVER=ON` | DBA + App team | W8 |
| 4.6 | `srvctl modify ons -remoteservers <STBY_nodes:6200>` on PRIM (and vice versa) | DBA | W8 |
| 4.7 | Firewall: ONS 6200 DC↔DR bidirectional | Network | W8 |
| 4.8 | FAN events test: `srvctl stop service -d PRIM -s MYAPP_TAC -drain_timeout 60` | — | W9 |
| 4.9 | Expected: UCP drains the application, reconnects to the other RAC node | App monitoring | W9 |
| 4.10 | Replay test: `ALTER SYSTEM KILL SESSION ...` mid-transaction | — | W9 |
| 4.11 | Expected: the application sees no error; `GV$REPLAY_STAT_SUMMARY` shows `requests_replayed > 0` | `fsfo_monitor.sql` section 7 | W9 |

### Deliverables

- Application integrated with UCP + TAC
- FAN events working cross-site (PRIM↔STBY)
- Replay test: instance crash → application sees no error

### Gate to Phase 5

- [ ] `GV$REPLAY_STAT_SUMMARY.requests_total > 0` after the test
- [ ] Drain test: 0 application errors during `srvctl stop service -drain_timeout`
- [ ] UCP pool metrics: `failover_type=TRANSACTION` visible in session_info
- [ ] FAN events visible on the client (`oracle.ucp.log=FINE`)

---

## 📋 Phase 5 — Integration testing (Weeks 10-13)

**Goal:** End-to-end testing of FSFO + TAC combinations; SLA validation (RTO/RPO); chaos engineering.

### Test cases

| # | Scenario | Expected outcome | SLA |
|---|----------|------------------|-----|
| T-1 | Planned FSFO-aware switchover | Drain → switch → services up on STBY; app sees no errors | 60 s |
| T-2 | `SHUTDOWN ABORT` on primary node 1 (node 2 still running) | FAN DOWN; UCP reroutes to node 2; no FSFO failover | ≤ 5 s |
| T-3 | `SHUTDOWN ABORT` of both PRIM nodes (DC site outage) | Observer (master on EXT) initiates FSFO; failover to STBY (DR); TAC replay | ≤ 45 s |
| T-4 | Network partition DC↔DR (Observer sees both) | Observer decides on quorum: failover to the side with a heartbeat | ≤ 45 s |
| T-5 | Network partition DC↔EXT (Observer master isolated) | Backup observer (obs_dr) takes over the master role; FSFO still active | ≤ 60 s |
| T-6 | Observer host down (all 3) | FSFO stays ENABLED but does not failover; alert to on-call; manual failover possible | alert < 60 s |
| T-7 | Rolling Oracle patch (switchover + patch + switchback) | Zero application downtime; TAC replay during each switchover | 0 errors |
| T-8 | Kill in-transaction session: `ALTER SYSTEM KILL SESSION 'sid,serial#'` | TAC replays the uncommitted commit; app OK | ≤ 2 s |
| T-9 | Full STBY drain (60 s) | Application drains fully; connection failover; 0 session-termination errors | 60 s |
| T-10 | AutoReinstate after failover | Old primary returns as standby with no intervention; broker SUCCESS | ≤ 5 min |

### Deliverables

- Test protocol with RTO/RPO measurements for every scenario
- Identification and resolution of regressions (if any)
- Business sign-off (SLAs met)

### Gate to Phase 6 (Go-Live)

- [ ] All 10 test scenarios passed
- [ ] RTO for T-3 ≤ 45 s (SLA)
- [ ] RPO = 0 across all tests (no committed transactions lost)
- [ ] Runbook [INTEGRATION-GUIDE § 6](INTEGRATION-GUIDE.md#6-operational-runbook) verified in practice
- [ ] On-call team trained (at least 2 people)

---

## 📋 Phase 6 — Go-Live + monitoring (ongoing)

**Goal:** Production; continuous monitoring; periodic drills.

### Ongoing tasks

| # | Task | Frequency | Tool |
|---|------|-----------|------|
| 6.1 | Monitor FSFO status | every 5 min (cron) | `bash/fsfo_monitor.sh -s PRIM -a` |
| 6.2 | Monitor TAC replay stats | every 1 h | `sql/fsfo_monitor.sql` section 7 |
| 6.3 | Monitor Observer health on the 3 hosts | every 1 min | `systemctl status dgmgrl-observer-{dc,dr,ext}` |
| 6.4 | Apply lag alert | real-time | Grafana + `V$DATAGUARD_STATS` |
| 6.5 | Review the PRIM/STBY alert log | daily | DBA on-call |
| 6.6 | Full multi-DB validation | weekly | `bash/validate_all.sh -l targets.lst` |
| 6.7 | Failover drill (planned test) | quarterly | [INTEGRATION-GUIDE § 6.1](INTEGRATION-GUIDE.md#61-planned-switchover-fsfo-aware) |
| 6.8 | Review ADRs + DESIGN.md | bi-annually | DBA + Security teams |

### Alerts

| Alert | Severity | Action |
|-------|----------|--------|
| FSFO `DISABLED` | CRITICAL | Page on-call DBA; check `ORA-16820/16825` |
| Apply lag ≥ 30 s (LagLimit) | CRITICAL | FSFO will not fire — check transport, network |
| Observer master down | HIGH | Backup should take over in ≤ 60 s; verify `SHOW OBSERVER` |
| TAC replay success rate < 80% | MEDIUM | App design issue — review `GV$REPLAY_STAT_SUMMARY.requests_failed` |
| Broker config `WARNING` | MEDIUM | Check `DBA_DG_BROKER_CONFIG_PROPERTIES` |

---

## 🚨 Risk matrix

**Top 8 deployment risks** (matching [checklist.html](../checklist.html) Risk Matrix):

| # | Risk | Severity | Description | Mitigation |
|---|------|----------|-------------|------------|
| **R1** | **Observer SPOF** | 🔴 HIGH | A single observer is a single point of failure in the FSFO decision chain | Observer HA — 3 observers in DC/DR/EXT (ADR-001); systemd `Restart=on-failure`; preemptive `SET MASTEROBSERVER` |
| **R2** | **Network partition** | 🔴 HIGH | Split-brain risk when the observer cannot see both sites | Master observer on a third site (EXT) — independent network path; quorum-based election |
| **R3** | **Reinstate failure** | 🟡 MED | Old primary fails to return as standby when Flashback is off | `FLASHBACK ON` on PRIM and STBY; correctly sized FRA; `AutoReinstate=TRUE` |
| **R4** | **Lag limit exceeded** | 🟡 MED | Apply lag > `LagLimit` blocks auto-failover | Continuous monitoring; threshold alert at 50% (15 s); SYNC transport under normal load |
| **R5** | **Non-replayable ops** | 🔴 HIGH | `ALTER SESSION`, `UTL_HTTP`, DDL inside a transaction abort TAC replay | Code review in Phase 4; `tac_replay_monitor.sql` section 5 scans V$SQL; refactor application code |
| **R6** | **Old JDBC drivers** | 🟡 MED | JDBC < 19c does not support TAC replay | Upgrade to `ojdbc11.jar` 19c+; verify via `V$SESSION_CONNECT_INFO` + `tac_full_readiness.sql` section 10 |
| **R7** | **FAN port blocked** | 🟡 MED | Firewall blocks ONS 6200 — no FAN events to UCP | Firewall matrix in Phase 0; pre-go-live test (`telnet scan-dr 6200` from app server); cross-site ONS bidirectional |
| **R8** | **Performance impact** | 🟢 LOW | Commit-outcome tracking adds ~3% overhead (LTXID writes) | Benchmark in Phase 5; size CPU/IO with a 10% margin; monitor `V$SYSTEM_EVENT` for `commit cleanouts` |

**Additional operational risks** (beyond the Top 8):

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| R-9  | Broker misconfiguration | 🟡 MED | `fsfo_configure_broker.sql` generator + DBA review in Phase 1 |
| R-10 | UCP misconfiguration | 🟡 MED | Code review; tests T-8, T-9 in Phase 5 |
| R-11 | Wallet expiry | 🟢 LOW | Password rotation per policy (90 days); monitoring |
| R-12 | No on-call RAC expertise | 🟡 MED | Training in Phase 5; [INTEGRATION-GUIDE § 6](INTEGRATION-GUIDE.md#6-operational-runbook) |

---

## ✅ Deployment checklist (final pre-Go-Live)

### FSFO

- [ ] `SHOW CONFIGURATION` = `SUCCESS`
- [ ] `SHOW FAST_START FAILOVER` = `ENABLED`
- [ ] `FastStartFailoverThreshold` = 30
- [ ] `FastStartFailoverLagLimit` = 30
- [ ] `FastStartFailoverAutoReinstate` = TRUE
- [ ] `ObserverOverride` = TRUE
- [ ] `ObserverReconnect` = 10
- [ ] 3 observers connected (obs_dc, obs_dr, obs_ext)
- [ ] Master Observer = `obs_ext`
- [ ] systemd units enabled + started on all 3 hosts
- [ ] Wallets on the 3 hosts (`/etc/oracle/wallet/observer-*`)
- [ ] Auto-failover test: PASS (RTO ≤ 45 s)
- [ ] Auto-reinstate test: PASS
- [ ] Observer HA failover test: PASS

### TAC

- [ ] `MYAPP_TAC` running on PRIM (role=PRIMARY) and auto-switches to STBY on switchover
- [ ] `MYAPP_RO` running (role=PHYSICAL_STANDBY)
- [ ] `failover_type=TRANSACTION`
- [ ] `commit_outcome=TRUE`
- [ ] `session_state_consistency=DYNAMIC`
- [ ] `retention_timeout=86400`
- [ ] `drain_timeout=300`
- [ ] `aq_ha_notifications=TRUE`

### UCP / Application

- [ ] `ojdbc11.jar` + `oracle-ucp.jar` + `ons.jar` version 19c+
- [ ] `ConnectionFactoryClassName=oracle.jdbc.replay.OracleDataSourceImpl`
- [ ] `FastConnectionFailoverEnabled=true`
- [ ] `ONSConfiguration` pointing to cross-site nodes
- [ ] TNS: two ADDRESS_LISTs (DC+DR) + `FAILOVER=ON`
- [ ] No DDL inside transactions
- [ ] No external calls (REST/JMS) inside transactions
- [ ] `DBMS_APP_CONT.REGISTER_CLIENT` for non-standard mutable objects

### Network

- [ ] Port 1521 open between app servers and SCAN (DC and DR)
- [ ] Port 6200 cross-site DC↔DR (for ONS/FAN)
- [ ] Port 1522 between observer hosts and SCAN (DC and DR) — for the DGMGRL static listener
- [ ] DC↔DR latency ≤ 2 ms (metro-area)
- [ ] EXT latency ≤ 50 ms

### Monitoring

- [ ] `bash/fsfo_monitor.sh` in crontab every 5 min
- [ ] Grafana dashboard with `V$DATAGUARD_STATS` + `GV$REPLAY_STAT_SUMMARY`
- [ ] Alerts on PagerDuty/OpsGenie for CRITICAL scenarios
- [ ] On-call runbook: [INTEGRATION-GUIDE § 6](INTEGRATION-GUIDE.md#6-operational-runbook)

### Documentation

- [ ] `README.md` up to date
- [ ] `DESIGN.md` up to date (ADRs signed off)
- [ ] `FSFO-GUIDE.md` reviewed by DBA lead
- [ ] `TAC-GUIDE.md` reviewed by App team lead
- [ ] `INTEGRATION-GUIDE.md` reviewed by Security + Network
- [ ] Runbook drill performed at least twice

---

## 👤 Author

**KCB Kris** | Date: 2026-04-23 | Version: 1.0

**Related:** [README.md](../README.md) • [DESIGN.md](DESIGN.md) • [FSFO-GUIDE.md](FSFO-GUIDE.md) • [TAC-GUIDE.md](TAC-GUIDE.md) • [INTEGRATION-GUIDE.md](INTEGRATION-GUIDE.md)
