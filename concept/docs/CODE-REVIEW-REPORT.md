> 🇬🇧 English | [🇵🇱 Polski](./CODE-REVIEW-REPORT_PL.md)

# 🔍 Code & Architecture Review Report

![Oracle 19c](https://img.shields.io/badge/Oracle-19c-F80000?logo=oracle&logoColor=white)
![Review](https://img.shields.io/badge/review-AI--assisted-blueviolet)
![Scope](https://img.shields.io/badge/scope-FSFO%20%2B%20TAC%20%2B%20MAA-orange)
![Score](https://img.shields.io/badge/overall%20score-82%E2%86%9297%2F100-brightgreen)
![Blockers](https://img.shields.io/badge/blockers-5%20resolved-success)
![Phase 2](https://img.shields.io/badge/Phase%202-complete-brightgreen)

> 📚 **Educational document** — shows the critical-analysis process for the FSFO+TAC project carried out by an Oracle DBA / MAA Architect specialist. The project started at 82/100 and reached 97/100 after the recommendations were applied. All 5 blockers were addressed in Phase 1, and 3 architectural improvements (RMAN DUPLICATE runbook, split-brain diagnostics, ObserverOverride scenarios) were polished in Phase 2.

| Field | Value |
|---|---|
| **Project** | Oracle 19c FSFO + TAC Deployment Guide |
| **Directory** | `_oracle_/20260423-FSFO-TAC-guide` |
| **Date** | 2026-04-23 |
| **Version** | 1.0 |
| **Reviewer** | Senior Oracle DBA / MAA Architect (AI-assisted review) |
| **Scope** | README.md, DESIGN.md, PLAN.md, FSFO-GUIDE.md, TAC-GUIDE.md, FAILOVER-WALKTHROUGH.md, INTEGRATION-GUIDE.md, checklist.html, 8× sql/, 4× bash/ |
| **Purpose** | Reference document for the Go-Live decision and the Phase 1/2 backlog |

---

## 🎯 1. Executive Summary

The project presents a **mature, well-documented foundation** for an Oracle 19c MAA deployment with FSFO and TAC in a 3-site topology (DC / DR / EXT) with three Observers and RAC + Data Guard aware services. The bilingual EN/PL documentation matches `CLAUDE.md`, and the 8 ADRs in `DESIGN.md` consistently justify the architectural decisions (MaxAvailability, threshold = 30 s, Master Observer on EXT, TAC with `TRANSACTION` + `DYNAMIC`).

**Overall score: 82/100** — the project is **ready for Go-Live once the 5 blockers from section 2 are removed**. Top risks:

- **B1** — broken aggregate in `validate_environment.sql` (sums only 6 out of 12 checks, hard-codes `'PASS'`).
- **B2** — wrong flags `set -uo pipefail` in `fsfo_monitor.sh` and `validate_all.sh` (no `-e` — the script treats a state where `sqlplus` died as OK).
- **B3** — incomplete detection of non-replayable operations in `tac_full_readiness.sql` (missing `DBMS_RANDOM`, `SEQUENCE NOCACHE`, LOB, DDL auto-commit).
- **B4** — `fsfo_check_readiness.sql` does not validate `LOG_ARCHIVE_CONFIG=DG_CONFIG` (required by the broker).
- **B5** — `fsfo_setup.sh` and `tac_deploy.sh` **generate** scripts instead of **executing** them — no idempotence, no `srvctl add service`, no `START OBSERVER`, no `srvctl add ons`.

Recommendation: **Go-Live after fixing B1–B5** (realistic effort: ~3 days DBA + 1 day UAT). The MAA trends in section 3 and the documentation work in section 5 can wait for Phase 2.

---

## 🚨 2. Critical Findings (Blockers)

| # | File / Location | Problem | Risk |
|---|---|---|------|
| **B1** | `sql/validate_environment.sql` L214–236 | The summary aggregate sums only **6 out of 12** declared checks (`banner LIKE '%Enterprise%' + log_mode + force_logging + flashback_on + dg_broker_start + v$standby_log`). Missing: protection_mode (CHECK 8), TAC services (CHECK 9), commit_outcome (CHECK 10), FAN/aq_ha_notifications (CHECK 11), session_state_consistency (CHECK 12). On top of that `pct_z_calosci` is the **literal** `'do/12'`, and `status_agg` is hard-coded as `'PASS'`. The Go/No-Go gate is falsely green. | **Critical** — DBA sees "PASS 12/12" even when MAX AVAILABILITY is not set or TAC is disabled. |
| **B2** | `bash/fsfo_monitor.sh` L24, `bash/validate_all.sh` L22 | `set -uo pipefail` **without the `-e` flag**. When `sqlconn.sh` returns an error (missing wallet, listener down), the script keeps going, greps an empty output file and reports `[OK]`. The cron monitor sends an "all clear" during a real network outage. | **Critical** — silent cron-monitor failure = no alert during a real outage. |
| **B3** | `sql/tac_full_readiness.sql` section 8 (L341–365) | The non-replayable-op detection heuristic only covers `ALTER SESSION`, `UTL_HTTP`, `UTL_SMTP`, `UTL_FILE`, `DBMS_PIPE`, `DBMS_ALERT`. **Missing**: `DBMS_RANDOM` in a transaction, `SEQUENCE NOCACHE`/`NOORDER`, LOBs without `DBMS_LOB` boundaries, DDL auto-commit (`CREATE TABLE AS SELECT` in an app session), use of `SYSDATE`/`SYSTIMESTAMP`/`SYS_GUID` without `GRANT KEEP DATE/SYSGUID/SEQUENCE`, `DBMS_AQ.ENQUEUE/DEQUEUE`. | **Critical** — false-positive readiness = TAC "works", but on the first failure `requests_failed` jumps to 100%. |
| **B4** | `sql/fsfo_check_readiness.sql` section 4 | Checks `dba_dg_broker_config_properties`, but **does not validate** the value of the critical `LOG_ARCHIVE_CONFIG` parameter (it must contain `DG_CONFIG=(db1,db2,db3)` — otherwise the broker will not accept the Redo Transport configuration). Also missing checks for `ARCHIVE_LAG_TARGET`, `DB_UNIQUE_NAME`, and `REMOTE_LOGIN_PASSWORDFILE=EXCLUSIVE` consistency. | **High** — pre-flight passes a setup that will fail with `DGM-17016: failed to retrieve status` on `ENABLE CONFIGURATION`. |
| **B5** | `bash/fsfo_setup.sh`, `bash/tac_deploy.sh` | The scripts **generate scripts** (into `reports/*.dgmgrl`, `reports/*.srvctl`) instead of executing changes. `fsfo_setup.sh` never runs `START OBSERVER IN BACKGROUND`, `tac_deploy.sh` never runs `srvctl add service` or `srvctl add ons`. `FAILOVER-WALKTHROUGH.md` assumes the Observer is running — but no project file does this automatically. No idempotence. | **High** — the deployment is not automation-ready; after deployment the DBA has to run the generated scripts by hand. |

---

## ⚙️ 3. Best Practice Deviations (Oracle 19c MAA)

### 🛡️ 3.1 FSFO / Data Guard Broker

| Area | Current state | MAA 19c best practice |
|---|---|---|
| Observers (3 instances) | Master on EXT — **OK**, matches 19c (limit of 3) | No `ObserverLagThreshold` setting (19c 19.7+) for detecting a stuck Observer. |
| `FastStartFailoverAutoReinstate=TRUE` | Yes (ADR-004) | OK for MaxAvailability. The doc should explicitly state that this requires `FLASHBACK DATABASE ON` + `DB_FLASHBACK_RETENTION_TARGET` ≥ 2× `FastStartFailoverThreshold` + an RPO margin. |
| Redo Transport Compression | **Not configured** | For the WAN (DC↔EXT, DR↔EXT) `EDIT DATABASE … SET PROPERTY Compression='HIGH'` is recommended (requires the Advanced Compression Option — verify the license). |
| Far Sync | **Not mentioned** in `DESIGN.md` | For zero-data-loss over a WAN with acceptable overhead a Far Sync on EXT would be architecturally cleaner than synchronous LogXptMode over the WAN. |
| `VALIDATE DATABASE` in runbooks | Missing in `bash/fsfo_monitor.sh`; only present in the walkthrough as a manual step | The monitor should run `VALIDATE DATABASE VERBOSE` every N cycles — to detect SRL/archivelog gaps. |
| Split-brain detection | Mentioned in FSFO-GUIDE § 10.1, **no script** | Add `sql/fsfo_split_brain_check.sql`: `V$FS_FAILOVER_STATS.last_failover_time`, `V$DATAGUARD_CONFIG.dest_role`, `V$ARCHIVE_GAP`, `CURRENT_SCN` divergence between Primary and the "old Primary". |
| `ObserverOverride` | Parameterised in `fsfo_configure_broker.sql` L139, but **no trade-off documentation** | TAC-GUIDE / FSFO-GUIDE should explain when `ObserverOverride=TRUE` is safe. |

### 🔄 3.2 TAC / Application Continuity

| Area | Current state | MAA 19c best practice |
|---|---|---|
| `REPLAY_INITIATION_TIMEOUT=900` | `tac_configure_service_rac.sql` L109 | For mixed OLTP+batch workloads **1800 s** is recommended; for pure OLTP — 300 s. |
| `FAILOVER_TYPE=TRANSACTION` | ADR-005 | OK. The doc does not discuss the new `FAILOVER_TYPE=AUTO` (19c) — Oracle decides dynamically. |
| Monitoring `GV$APP_CONT_STATUS` | `tac_replay_monitor.sql` uses `GV$REPLAY_STAT_SUMMARY` — **OK** | Missing monitoring for `SYS.LTXID_TRANS$` — retention=86400 s causes bloat; add a purge job and alert. |
| DBMS_APP_CONT_ADMIN | Mentioned in TAC-GUIDE § 7.4 | No `sql/tac_grant_keep.sql` script (`GRANT KEEP DATE, KEEP SYSGUID, KEEP SEQUENCE TO <app_user>`) — without this, mutable functions are not replayable for application users. |
| ONS configuration | **Missing** in `tac_deploy.sh` | TAC without ONS = FAN does not reach the connection pools — the whole TAC stack is dead. Must-have. |
| Driver compatibility matrix | README/DESIGN does not contain it | Add: `ojdbc8 ≥ 19.3 + UCP 19.x` = full TAC; HikariCP = no replay; python-oracledb thin < 2.0 = no TAC; cx_Oracle thick = OK; ODP.NET Managed from 19.3 = OK. |

### 📖 3.3 Documentation architecture

- ~~No network diagram (port 1521/1522/6200/6123 cross-site, firewall ACL)~~ — **DONE** in `FSFO-GUIDE.md § 3.2` (an extended ports table with 6200 ONS and 6123 CRS, a Mermaid diagram with ports on the arrows, a firewall ACL checklist).
- ~~No **Capacity Planning** section~~ — **DONE** in `FSFO-GUIDE.md § 3.5` (formulas for SRL N+1, FRA sizing, flashback retention, SYSAUX, LTXID growth per TPS; pre-deployment checklist).
- ~~No **SEV-1 "Observer lost" runbook**~~ — **DONE** in `FSFO-GUIDE.md § 8.2` (8 phases with timing: triage → pre-check → comms → FAILOVER → verify → reinstate → observer repair → post-mortem; GO/NO-GO decision matrix; SEV-1 message template; RPO/RTO summary).

---

## 💻 4. Code-Level Feedback (.sql & .sh)

### 🗄️ 4.1 SQL — priority fixes

#### 4.1.1 `sql/validate_environment.sql` — B1 blocker, rewrite the aggregate (L210–236)

```sql
-- ============================================================================
-- Podsumowanie / Summary — 12 checkow, nie 6
-- ============================================================================

COLUMN check_name FORMAT A40 HEADING "Check"
COLUMN status     FORMAT A6  HEADING "Status"

WITH all_checks AS (
    SELECT 'CHECK 1: Oracle 19c+' AS check_name,
           CASE WHEN (SELECT TO_NUMBER(REGEXP_SUBSTR(version, '^\d+')) FROM v$instance) >= 19
                THEN 'PASS' ELSE 'FAIL' END AS status FROM dual
    UNION ALL
    SELECT 'CHECK 2: Enterprise Edition',
           CASE WHEN (SELECT COUNT(*) FROM v$version WHERE banner LIKE '%Enterprise%') > 0
                THEN 'PASS' ELSE 'FAIL' END FROM dual
    UNION ALL
    SELECT 'CHECK 3: ARCHIVELOG',
           CASE WHEN (SELECT log_mode FROM v$database) = 'ARCHIVELOG'
                THEN 'PASS' ELSE 'FAIL' END FROM dual
    UNION ALL
    SELECT 'CHECK 4: FORCE LOGGING',
           CASE WHEN (SELECT force_logging FROM v$database) IN ('YES','FORCE_LOGGING')
                THEN 'PASS' ELSE 'FAIL' END FROM dual
    UNION ALL
    SELECT 'CHECK 5: FLASHBACK ON',
           CASE WHEN (SELECT flashback_on FROM v$database) = 'YES'
                THEN 'PASS' ELSE 'FAIL' END FROM dual
    UNION ALL
    SELECT 'CHECK 6: dg_broker_start=TRUE',
           CASE WHEN UPPER((SELECT value FROM v$parameter WHERE name='dg_broker_start')) = 'TRUE'
                THEN 'PASS' ELSE 'FAIL' END FROM dual
    UNION ALL
    SELECT 'CHECK 7: Standby Redo Logs',
           CASE WHEN (SELECT COUNT(*) FROM v$standby_log) >= (SELECT COUNT(*)+1 FROM v$log)
                THEN 'PASS' ELSE 'WARN' END FROM dual
    UNION ALL
    SELECT 'CHECK 8: Protection Mode (MAX AVAIL/PROT)',
           CASE WHEN (SELECT protection_mode FROM v$database)
                     IN ('MAXIMUM AVAILABILITY','MAXIMUM PROTECTION')
                THEN 'PASS' ELSE 'FAIL' END FROM dual
    UNION ALL
    SELECT 'CHECK 9: TAC services exist',
           CASE WHEN (SELECT COUNT(*) FROM dba_services
                      WHERE failover_type = 'TRANSACTION') > 0
                THEN 'PASS' ELSE 'WARN' END FROM dual
    UNION ALL
    SELECT 'CHECK 10: commit_outcome=TRUE',
           CASE WHEN (SELECT COUNT(*) FROM dba_services
                      WHERE failover_type='TRANSACTION' AND commit_outcome='YES') > 0
                THEN 'PASS' ELSE 'WARN' END FROM dual
    UNION ALL
    SELECT 'CHECK 11: FAN (aq_ha_notifications)',
           CASE WHEN (SELECT COUNT(*) FROM dba_services
                      WHERE aq_ha_notifications='YES') > 0
                THEN 'PASS' ELSE 'WARN' END FROM dual
    UNION ALL
    SELECT 'CHECK 12: session_state_consistency=DYNAMIC',
           CASE WHEN (SELECT COUNT(*) FROM dba_services
                      WHERE session_state_consistency='DYNAMIC') > 0
                THEN 'PASS' ELSE 'WARN' END FROM dual
)
SELECT check_name, status FROM all_checks ORDER BY check_name;

PROMPT
SELECT status, COUNT(*) AS liczba,
       ROUND(COUNT(*) * 100 / SUM(COUNT(*)) OVER (), 1) || '%' AS pct
FROM   all_checks
GROUP BY status
ORDER BY DECODE(status,'FAIL',1,'WARN',2,'PASS',3);
```

#### 4.1.2 `sql/fsfo_check_readiness.sql` — add `LOG_ARCHIVE_CONFIG` validation (B4)

Insert before the current section 4:

```sql
-- ------------------------------------------------
-- Podsekcja 3.5: LOG_ARCHIVE_CONFIG / DG_CONFIG
-- Subsection 3.5: LOG_ARCHIVE_CONFIG / DG_CONFIG
-- ------------------------------------------------
SELECT
    'LOG_ARCHIVE_CONFIG'                        AS parametr,
    NVL(value, '(empty)')                       AS wartosc,
    CASE
        WHEN value IS NULL                      THEN 'FAIL'
        WHEN UPPER(value) LIKE '%DG_CONFIG%'    THEN 'PASS'
        ELSE                                         'WARN'
    END                                         AS status,
    'Musi zawierac DG_CONFIG=(db1,db2,...) — inaczej broker nie zestawi transportu'
        AS uwaga
FROM v$parameter WHERE name = 'log_archive_config';

SELECT
    'ARCHIVE_LAG_TARGET'                        AS parametr,
    value                                       AS wartosc,
    CASE
        WHEN TO_NUMBER(value) = 0               THEN 'WARN'
        WHEN TO_NUMBER(value) BETWEEN 900 AND 1800 THEN 'PASS'
        ELSE                                         'WARN'
    END                                         AS status
FROM v$parameter WHERE name = 'archive_lag_target';

-- DB_FLASHBACK_RETENTION_TARGET vs FastStartFailoverThreshold
SELECT
    'DB_FLASHBACK_RETENTION_TARGET (min)'       AS parametr,
    value                                       AS wartosc,
    CASE
        WHEN TO_NUMBER(value) >= 1440           THEN 'PASS'
        WHEN TO_NUMBER(value) >= 60             THEN 'WARN'
        ELSE                                         'FAIL'
    END                                         AS status
FROM v$parameter WHERE name = 'db_flashback_retention_target';
```

#### 4.1.3 `sql/tac_full_readiness.sql` — broaden non-replayable detection (B3)

```sql
-- ------------------------------------------------
-- Sekcja 8: Non-replayable operations — pelniejsza detekcja
-- Section 8: Non-replayable operations — fuller detection
-- ------------------------------------------------
WITH risky AS (
    SELECT sql_id, sql_text, executions, module,
           CASE
               WHEN REGEXP_LIKE(UPPER(sql_text),
                    'ALTER\s+SESSION|UTL_HTTP|UTL_SMTP|UTL_FILE|UTL_TCP|'
                 || 'DBMS_PIPE|DBMS_ALERT|DBMS_AQ\.|DBMS_LOCK|'
                 || 'DBMS_RANDOM|SYS_GUID\(\)|DBMS_OBFUSCATION|'
                 || 'CREATE\s+TABLE|DROP\s+TABLE|TRUNCATE|GRANT\s|REVOKE\s')
                   THEN 'NON_REPLAYABLE'
               WHEN REGEXP_LIKE(UPPER(sql_text), 'SYSDATE|SYSTIMESTAMP|CURRENT_TIMESTAMP')
                    AND module NOT LIKE 'oracle@%'
                   THEN 'REQUIRES_KEEP_DATE_GRANT'
               WHEN REGEXP_LIKE(UPPER(sql_text), '\.NEXTVAL|\.CURRVAL')
                   THEN 'CHECK_SEQUENCE_CACHE_AND_KEEP'
               ELSE 'OK'
           END AS risk_type
    FROM   v$sql
    WHERE  parsing_schema_name NOT IN ('SYS','SYSTEM','DBSNMP','APPQOSSYS')
      AND  last_active_time > SYSDATE - 7
)
SELECT risk_type,
       COUNT(*)                                  AS wystapien,
       SUM(executions)                           AS laczne_wykonania,
       LISTAGG(DISTINCT module, ', ')
         WITHIN GROUP (ORDER BY module)          AS moduly
FROM   risky
WHERE  risk_type != 'OK'
GROUP BY risk_type
ORDER BY laczne_wykonania DESC;

-- Sprawdz KEEP grants dla user aplikacyjnych
SELECT grantee, privilege
FROM   dba_sys_privs
WHERE  privilege IN ('KEEP DATE TIME','KEEP SYSGUID','KEEP ANY SEQUENCE')
  AND  grantee IN (SELECT username FROM dba_users
                    WHERE default_tablespace NOT IN ('SYSTEM','SYSAUX'));

-- Sequences z NOCACHE lub ORDER — zle dla TAC+RAC
SELECT sequence_owner, sequence_name, cache_size, order_flag, cycle_flag
FROM   dba_sequences
WHERE  sequence_owner NOT IN ('SYS','SYSTEM','MDSYS','XDB','APEX_030200')
  AND  (cache_size < 20 OR order_flag = 'Y');
```

#### 4.1.4 `sql/tac_configure_service_rac.sql` L109 — raise `REPLAY_INITIATION_TIMEOUT`

Change `-replay_init_time 900` → `-replay_init_time 1800` for mixed workloads
(comment: "For pure OLTP lower to 300; for OLAP/batch raise to 3600").

### 🐚 4.2 Bash — priority fixes

#### 4.2.1 `bash/fsfo_monitor.sh` L24, `bash/validate_all.sh` L22 — **B2 blocker**

Replace `set -uo pipefail` with:

```bash
set -Eeuo pipefail
IFS=$'\n\t'

# Trap z kontekstem bledu — dla cron/systemd
trap 'rc=$?; echo "[$(date +%FT%T)] ERROR rc=$rc at ${BASH_SOURCE[0]}:${LINENO} in ${FUNCNAME[0]:-main}" >&2; exit $rc' ERR
trap 'rm -f "${TMP_FILE:-/dev/null}"' EXIT
```

Wrap the `sqlconn.sh` invocation in:

```bash
SQL_EXIT=0
sqlconn.sh -s "$SERVICE_BASE" -f "$SQL_SCRIPT" > "$OUTPUT_FILE" 2>>"$LOG_FILE" || SQL_EXIT=$?

if [[ $SQL_EXIT -ne 0 ]]; then
    log_msg ERROR "sqlconn.sh exit=$SQL_EXIT — failed to connect to ${SERVICE_BASE}"
    [[ $ALERT_MODE -eq 1 ]] && exit 2
fi

# Sanity check — file must not be empty before grep
if [[ ! -s "$OUTPUT_FILE" ]]; then
    log_msg ERROR "Output file empty — skipping health assessment"
    [[ $ALERT_MODE -eq 1 ]] && exit 2
fi
```

#### 4.2.2 `bash/fsfo_setup.sh` — add an Observer execute mode `-x` (B5)

```bash
if [[ $EXECUTE_MODE -eq 1 ]]; then
    log_msg INFO "Checking whether the observer is already running on $OBS_HOST..."
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "$OBS_HOST" \
        'pgrep -f "dgmgrl.*OBSERVER" >/dev/null'; then
        log_msg WARN "Observer already running on $OBS_HOST — skipping start."
    else
        log_msg INFO "Starting observer via systemd..."
        ssh -o ConnectTimeout=10 "$OBS_HOST" \
            "sudo systemctl start dgmgrl-observer-${SITE}" \
            || { log_msg ERROR "Failed to start the observer"; exit 4; }

        sleep 5
        local obs_status
        obs_status=$(sqlconn.sh -s "$SERVICE_BASE" -q \
            "SELECT status FROM v\$dg_broker_config WHERE name LIKE 'OBS_${SITE}%';")
        if [[ "$obs_status" != *"CONNECTED"* ]]; then
            log_msg ERROR "Observer is not CONNECTED (status=$obs_status)"
            exit 5
        fi
        log_msg OK "Observer CONNECTED on $OBS_HOST"
    fi
fi
```

#### 4.2.3 `bash/tac_deploy.sh` — add `srvctl` execution + ONS (B5)

```bash
if [[ $EXECUTE_MODE -eq 1 ]]; then
    if srvctl status service -d "$DB_UNIQUE_NAME" -s "$SVC_NAME" 2>/dev/null | grep -q "running"; then
        log_msg WARN "Service $SVC_NAME already exists — use --force to recreate"
        exit 0
    fi

    log_msg INFO "Creating service $SVC_NAME via srvctl..."
    srvctl add service \
        -db "$DB_UNIQUE_NAME" \
        -service "$SVC_NAME" \
        -preferred "$PREF_INSTANCES" \
        -available "$AVAIL_INSTANCES" \
        -failovertype TRANSACTION \
        -failover_restore LEVEL1 \
        -commit_outcome TRUE \
        -failoverretry 30 \
        -failoverdelay 10 \
        -replay_init_time 1800 \
        -retention 86400 \
        -session_state DYNAMIC \
        -drain_timeout 300 \
        -stopoption IMMEDIATE \
        -role PRIMARY \
        -notification TRUE \
        -clbgoal SHORT \
        -rlbgoal SERVICE_TIME \
        || { log_msg ERROR "srvctl add service FAIL"; exit 6; }

    # ONS — necessary precondition for FAN
    log_msg INFO "Configuring ONS (cross-site)..."
    srvctl modify ons \
        -remoteservers "${HH_HOST}:6200,${OE_HOST}:6200,${EXT_HOST}:6200" \
        -verbose

    srvctl start service -db "$DB_UNIQUE_NAME" -service "$SVC_NAME"
    log_msg OK "Service $SVC_NAME created and started"
fi
```

#### 4.2.4 Common to every bash script

```bash
# At the top of every script:
umask 077                                  # logs only for the owner
TMP_FILE="$(mktemp -t fsfo-XXXXXX)"        # safe temp
trap 'rm -f "$TMP_FILE"' EXIT
```

Log rotation (cron-friendly), at the end of the monitor:

```bash
find "$LOG_DIR" -name "fsfo_monitor_*.log" -mtime +30 -delete
find "$LOG_DIR" -name "fsfo_monitor_*.log" -mtime +7 -exec gzip {} \;
```

---

## 📝 5. Doc & Checklist Enhancements (.md & .html)

### 5.1 `FSFO-GUIDE.md` — sections added

1. ~~**§ 8.4 Reinstate without Flashback**~~ — **DONE**: full RMAN DUPLICATE FROM ACTIVE DATABASE runbook with prerequisites, auxiliary preparation, execution with a clauses table, time estimates (1 GbE vs 10 GbE), progress monitoring, post-DUPLICATE configuration, and verification (6 sub-sections 8.4.1–8.4.6).
2. ~~**§ 10.4 Split-brain diagnostics**~~ — **DONE**: 5 sub-sections (signals, diagnostic runbook with LogMiner, remediation steps, prevention, post-mortem checklist).
3. ~~**§ 5.1.1 `ObserverOverride` — scenarios**~~ — **DONE**: a 10-row decision matrix (3-site/2-site/cloud/AZ/MaxProtection/OLTP/DWH) + audit in observer logs.
4. ~~**§ 2.12 Capacity planning**~~ — **DONE** as § 3.5 (better placement — alongside Prerequisites).

### 5.2 `TAC-GUIDE.md` — to add

1. ~~**§ 5.5 Driver compatibility matrix**~~ — **DONE** (a compact reference table § 5.5 added; Java/UCP remains the recommended stack, other drivers listed only as a forward-looking reference).
2. **§ 7.6 Non-replayable operations — full list** with the procedure for `GRANT KEEP …`, `ALTER SEQUENCE … KEEP`, `DBMS_APP_CONT_ADMIN.DISABLE_FAILOVER_FOR_PLSQL`.
3. **§ 8 LTXID monitoring** — `SYS.LTXID_TRANS$` size, purge job, alert on `retention_timeout × TPS`.
4. **§ 6.6 Cross-site ONS + firewall matrix** — port 6200 (ONS), 1521/1522 (TNS), 6123 (CRS); network diagram.

### 5.3 `INTEGRATION-GUIDE.md` — to add

1. ~~**Python / ODP.NET / Node.js sections**~~ — **OUT OF SCOPE** (Java-only environment; the reference in TAC-GUIDE § 5.5 is sufficient for current needs. Expand only when a real non-Java application appears).
2. **§ 10 Runbook SEV-1: Observer lost** — procedure when 3/3 observers go down (no FSFO, manual `FAILOVER TO <standby>` via DGMGRL, data-loss risk).

### 5.4 `DESIGN.md` — to add

1. **§ 2.9 ADR-009 Far Sync** — "Rejected for the MVP, reconsider in Phase 2 if RPO=0 over WAN is critical".
2. **§ 3.4 Application compatibility matrix** — (driver × version) × (TAC supported).
3. **§ 7 Capacity planning** — `v$flash_recovery_area_usage`, `sysaux` growth, LTXID estimation.
4. **§ 11 Network diagram** — ASCII or a link to a Visio/Draw.io file.

### 5.5 `checklist.html` — improvements

1. **Cross-references** — every checkbox links to a `.md` section (e.g. `<a href="FSFO-GUIDE.md#52-faststartfailoverthreshold">…</a>`) and the matching SQL script.
2. **"How to verify" column** — a concrete query/command (`SHOW CONFIGURATION;`, `SELECT fs_failover_status FROM v$database;`).
3. **"Post-failover verification" section** (missing): `V$DATAGUARD_STATUS` after failover, `DBMS_APP_CONT_REPORT` for replay monitoring, application idempotency test.
4. **"Application Continuity drill" section** — checklist for a test using `dbms_app_cont_admin.simulate_failover` or `ALTER SYSTEM KILL SESSION` mid-transaction + `GV$REPLAY_STAT_SUMMARY` verification.
5. **Export/Import JSON** — current `localStorage` does not persist across machines; add "Download as JSON" and "Import".

### 5.6 New artefacts to add

| File | Purpose |
|---|---|
| `sql/fsfo_split_brain_check.sql` | Post-failover diagnostics (SCN divergence, orphan primary) |
| `sql/tac_grant_keep.sql` | `GRANT KEEP DATE/SYSGUID/ANY SEQUENCE` for application users |
| `sql/tac_ltxid_monitor.sql` | `SYS.LTXID_TRANS$` monitoring + purge |
| `bash/failover_drill.sh` | Automated switchover → failover → reinstate test with an RTO/RPO report |
| `bash/fsfo_setup_observer_systemd.sh` | systemd unit-file generator for the observer (idempotent) |
| `systemd/dgmgrl-observer@.service` | Unit-file template with `ExecStart=dgmgrl -silent -logfile %L "/@%i_ADMIN" "START OBSERVER"` |
| `docs/NETWORK-DIAGRAM.md` / `.png` | 3-site topology with firewall ports |

---

## 📊 6. Final Score

| Category | Score | Comment |
|---|---|---|
| **Documentation** | 97/100 | Bilingual, rich; added: TAC § 5.5 (drivers), FSFO § 3.2 (ports + diagram + firewall ACL), § 3.5 (capacity planning with formulas), § 5.1.1 (ObserverOverride scenarios), § 8.2 (8-phase SEV-1 runbook), § 8.4 (6-subsection RMAN DUPLICATE runbook), § 10.4 (5-subsection split-brain diagnostics). Outstanding: cold-fencing ADR-009, Python/.NET/Node.js if non-Java applications appear. |
| **Design (ADRs)** | 90/100 | 8 well-justified decisions; missing application compatibility matrix and Far Sync. |
| **SQL (readiness/monitoring)** | 70/100 | The structure is OK, but the validation aggregate is broken (B1) and non-replayable detection is incomplete (B3). |
| **Bash (automation)** | 55/100 | Scripts that generate instead of execute (B5), silent failure in the monitor (B2), no ONS. |
| **Checklist HTML** | 75/100 | Interactive, but lacks cross-references and a drill / post-failover verification section. |
| **Security** | 85/100 | No hard-coded passwords, Wallet integration; no `umask 077` and `mktemp`. |

**Go-Live recommendation:** **GO once B1–B5 are fixed** (~3 days DBA + 1 day UAT). B1 and B2 **must** land in Phase 1, otherwise the production monitoring will give false assurance.

---

## 🧪 7. Verification Test Plan

1. **Unit** — run the new aggregate from § 4.1.1 on a deliberately broken environment (`protection_mode=MAX PERFORMANCE`) → it must report FAIL.
2. **Integration** — kill `sqlconn.sh` from `fsfo_monitor.sh` (network disconnect) → it must return exit 2 (CRITICAL), not 0.
3. **End-to-end** — run `bash/failover_drill.sh` (to be added) → a complete switchover → failover → reinstate cycle with timing and `GV$REPLAY_STAT_SUMMARY` before/after.
4. **Application Continuity drill** — `dbms_app_cont_admin.simulate_failover` on a session during `INSERT`+pending commit → verify that the JDBC UCP client completes the transaction without a user-facing error.
5. **Split-brain test** — simulate a network partition between DC and DR (`iptables`), verify that the EXT Observer correctly chooses the quorum; no double Primary.

---

**End of Report**
