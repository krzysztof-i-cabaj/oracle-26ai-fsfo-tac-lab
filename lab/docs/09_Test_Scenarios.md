> 🇬🇧 English | [🇵🇱 Polski](./09_Test_Scenarios_PL.md)

# 09 — FSFO and TAC Test Scenarios (VMs2-install)

> **Goal:** Systematically exercise 6 scenarios demonstrating Maximum Availability in Oracle 26ai:
> 1. Planned switchover (PRIM ↔ STBY).
> 2. Unplanned failover (kill primary with FSFO).
> 3. TAC replay during a transaction.
> 4. Apply lag exceeded (FSFO blocked).
> 5. Master Observer outage (multi-Observer redundancy).
> 6. Readiness validation (`validate_env.sh`).

> **Prereq:** documents 01–08 completed, FSFO `SYNCHRONIZED`, `MYAPP_TAC` active, multi-Observer configured (Master + 2 Backup), `TestHarness` compiled on `client01`.

---

## 0. Pre-flight before the scenarios

### 0.1. Environment validation

```bash
# From prim01 as oracle
bash /tmp/scripts/validate_env.sh --full
# All statuses PASS = environment ready. FAIL = fix before you start.
```

### 0.2. Server-side checklist (7 items)

```bash
# 1. Service MYAPP_TAC with the correct TAC attributes (F-02)
ssh oracle@prim01 ". ~/.bash_profile && srvctl config service -db PRIM -service MYAPP_TAC | \
   grep -E 'Failover|Commit|Session State|Retention|Replay|Drain|Pluggable'"
# Expected:
#   Pluggable database name: APPPDB
#   Failover type: TRANSACTION
#   Failover restore: LEVEL1                     ← F-02
#   Commit Outcome: true
#   Session State Consistency: DYNAMIC
#   Retention: 86400 seconds
#   Replay Initiation Time: 1800 seconds
#   Drain timeout: 300 seconds
#   Notification: TRUE

# 2. ONS on stby01 running under systemd (F-13)
ssh root@stby01 "systemctl is-active oracle-ons.service && ss -ntlp | grep ':6[12]00'"
# Expected: 'active' + LISTEN *:6200 and 127.0.0.1:6100

# 3. Cross-site ONS on PRIM RAC
ssh grid@prim01 ". ~/.bash_profile && srvctl config ons | grep -i remote"
# Remote port: 6200

# 4. Broker SUCCESS + FSFO ENABLED (from infra01 — wallet only there)
ssh oracle@infra01 "dgmgrl -silent /@PRIM_ADMIN 'SHOW CONFIGURATION'" | tr '\n' ' ' | \
   grep -oE "Configuration Status:[[:space:]]*\w+|Fast-Start Failover:[[:space:]]*\w+"
# Configuration Status: SUCCESS
# Fast-Start Failover: ENABLED

# 5. Multi-Observer active (Master + 2 Backup)
ssh oracle@infra01 "dgmgrl -silent /@PRIM_ADMIN 'SHOW OBSERVERS'" | grep -E "obs_(ext|dc|dr)"
# obs_ext - Master    (infra01)
# obs_dc  - Backup    (prim01)
# obs_dr  - Backup    (stby01)

# 6. STBY in Active Data Guard mode: OPEN READ ONLY WITH APPLY + PDB READ ONLY
ssh oracle@stby01 ". ~/.bash_profile && sqlplus -s / as sysdba <<'EOF'
SET PAGESIZE 0 FEEDBACK OFF
SELECT 'CDB / ' || open_mode FROM v\$database;
SELECT name || ' / ' || open_mode FROM v\$pdbs WHERE name <> 'PDB\$SEED';
EXIT
EOF"
# Expected:
#   CDB    / READ ONLY WITH APPLY     ← Real-Time Query Active DG
#   APPPDB / READ ONLY                ← PDB in read-only mode
# If CDB=MOUNTED or PDB=MOUNTED → SAVE STATE drifted out of sync
# with apply (rare, section 0.3 fallback).

# 6.a. Oracle Restart startoption (after a stby01 reboot OPEN RO is automatic)
ssh oracle@stby01 "srvctl config database -db STBY | grep -E 'Start option|Open mode'"
# Expected: Start option: read only (NOT 'mount')

# 7. TestHarness client ready on client01
ssh oracle@client01 "ls -la /opt/lab/src/TestHarness.class /opt/lab/jars/*.jar | wc -l"
# >= 6 files (TestHarness.class + 5 jars)

# 8. MYAPP_TAC service registered in Oracle Restart on stby01 (CRITICAL for auto-start after failover!)
ssh oracle@stby01 ". ~/.bash_profile && srvctl config service -db STBY -service MYAPP_TAC | \
   grep -E 'Service role|Failover type|Failover restore'"
# Expected:
#   Service role: PRIMARY                ← service activates only when STBY becomes PRIMARY
#   Failover type: TRANSACTION
#   Failover restore: LEVEL1
# No output / "PRCD-1014" = service not registered in Oracle Restart.
# Fix: ssh oracle@stby01 'bash /tmp/scripts/setup_tac_services_stby.sh'
# Without this, after failover you must manually run tac_service_resume.sh (FIX-095 fallback).
```

### 0.3. Fallback for STBY in MOUNTED (rare — when SAVE STATE drifts)

> **In the recommended configuration this step is not needed.** `create_standby_broker.sh` runs `ALTER PLUGGABLE DATABASE ALL SAVE STATE` after creating STBY and `srvctl modify database -startoption "READ ONLY"`, so after every `STARTUP`/reboot of stby01 the database and PDBs open automatically in `READ ONLY WITH APPLY` (Real-Time Query Active DG).
>
> The workaround below is needed **only** when:
> - `create_standby_broker.sh` was not run in full (manual path from docs/06 — check whether the Active DG section was executed),
> - or after a manual `STARTUP NOMOUNT` / `STARTUP MOUNT` (e.g. after RMAN restore) — then the SAVE STATE state is not applied until you reopen the PDBs and save state again.

```bash
# 1. Broker APPLY-OFF (from infra01)
ssh oracle@infra01 "dgmgrl -silent /@PRIM_ADMIN 'EDIT DATABASE stby SET STATE=APPLY-OFF'"

# 2. Open CDB + PDB in READ ONLY and SAVE state (will survive the next STARTUP)
ssh oracle@stby01 ". ~/.bash_profile && sqlplus -s / as sysdba <<EOF
ALTER DATABASE OPEN READ ONLY;
ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY;
ALTER PLUGGABLE DATABASE ALL SAVE STATE;
EXIT
EOF"

# 3. Oracle Restart startoption (idempotent — done to be sure)
ssh oracle@stby01 "srvctl modify database -db STBY -startoption 'READ ONLY'"

# 4. Broker APPLY-ON — back to Real-Time Query
ssh oracle@infra01 "dgmgrl -silent /@PRIM_ADMIN 'EDIT DATABASE stby SET STATE=APPLY-ON'"
```

### 0.4. Gotchas that will keep coming up

> 💡 **Wallet location:** the auto-login wallet `/etc/oracle/wallet/obs_*` is **on every host with an Observer** (infra01: `obs_ext`, prim01: `obs_dc`, stby01: `obs_dr`). Connecting via the password-less alias (`/@PRIM_ADMIN`, `/@STBY_ADMIN`) works **only from a host that has the wallet**. From `client01` (no Observer) you must either SSH to a host with the wallet or use an explicit password `sys/Oracle26ai_LAB!@PRIM_ADMIN`.
>
> 💡 **dgmgrl multiline grep:** the `SHOW CONFIGURATION` / `SHOW FAST_START FAILOVER` commands in 26ai return **multi-line output**. Plain `grep PATTERN` may return 0 hits even though the pattern is in the output. Use `tr '\n' ' '` to flatten before grep:
> ```bash
> dgmgrl -silent /@PRIM_ADMIN 'SHOW CONFIGURATION' | tr '\n' ' ' | grep -oE "Status:[[:space:]]*\w+"
> ```
>
> 💡 **TestHarness launched via helper:** path `/tmp/src/TestHarness.java` after compilation (`javac`) on client01. All scenarios below use the following command to launch TestHarness in the background:
> ```bash
> # Shortcut used in the scenarios (Java 17 requires --add-opens, F-09):
> ssh oracle@client01 'cd /opt/lab/src && \
>     java --add-opens=java.base/java.lang=ALL-UNNAMED \
>          --add-opens=java.base/java.util=ALL-UNNAMED \
>          --add-opens=java.base/jdk.internal.misc=ALL-UNNAMED \
>          --add-opens=java.base/sun.nio.ch=ALL-UNNAMED \
>          -cp "/opt/lab/jars/*:." TestHarness' &
> ```
> APP_PASSWORD does not need to be set — TestHarness has a fallback to `Oracle26ai_LAB!` (lab convention).

---

## Scenario 1 — Planned switchover (PRIM → STBY → PRIM)

### Goal
Demonstrate planned switching of the Primary role to Standby (and back) **without data loss** and with minimal application downtime.

### Steps

**1. Run `TestHarness` in the background on `client01`** (helper from section 0.4).

**2. From `infra01` perform validation and switchover:**
```bash
ssh oracle@infra01
dgmgrl /@PRIM_ADMIN
```
```text
DGMGRL> SHOW CONFIGURATION;
   Configuration Status:  SUCCESS
   Fast-Start Failover:   ENABLED
   Protection Mode:       MaxAvailability

DGMGRL> VALIDATE DATABASE STBY;
   Database Role:           physical standby database
   Ready for Switchover:    Yes
   Ready for Failover:      Yes (Primary Running)

DGMGRL> SWITCHOVER TO STBY;
   Performing switchover NOW, please wait...
   New primary database "STBY" is opening...
   Switchover succeeded, new primary is "STBY"

DGMGRL> SHOW CONFIGURATION;
   Members:
     STBY - Primary database              ← now primary
       PRIM - Physical standby database   ← now standby
   Configuration Status: SUCCESS
```

**3. In the `TestHarness` console you will see drain + reconnect:**
```
[54] SUCCESS: PRIM1  SID=456  rows=1
[55] RECOVERABLE (TAC replay/failover): 1089 - ORA-01089: immediate shutdown
[56] RECOVERABLE (TAC replay/failover): 3113 - ORA-03113: end-of-file
[57] SUCCESS: STBY  SID=123  rows=1   ← client now connects to STBY
```

> ⚠ **Service start on the new primary (stby01) — Oracle Restart vs fallback.** stby01 has **Grid Infrastructure for a Standalone Server (Oracle Restart)**, so the host-level CRS automatically starts the database and its services.
>
> **Recommended state (if `setup_tac_services_stby.sh` / docs/08 Step 1.5 was executed):**
> The `MYAPP_TAC` service is registered in Oracle Restart on stby01 with `-role PRIMARY`. After promote, CRS starts it within 5–15 s. Check:
> ```bash
> ssh oracle@stby01 ". ~/.bash_profile && srvctl status service -db STBY -service MYAPP_TAC"
> # Service MYAPP_TAC is running on database STBY    ← OK, nothing to do
> ```
>
> **Fallback (FIX-095) — when the service did NOT start automatically** (e.g. step 1.5 from docs/08 was not executed or Oracle Restart has an issue):
> ```bash
> ssh oracle@stby01 ". ~/.bash_profile && bash /tmp/scripts/tac_service_resume.sh"
> # The helper checks role + service and runs DBMS_SERVICE.START_SERVICE if needed.
> ```
> Name gotchas: `'MYAPP_TAC'` → ORA-44773 (case); `'myapp_tac.lab.local'` → ORA-44304 (domain). Only `'myapp_tac'` lowercase. The helper uses the correct form.
>
> Switchover the other way (`STBY → PRIM`): Grid CRS on prim01/02 starts the service without intervention — analogous to Oracle Restart on stby01 for the PRIM→STBY direction.

**4. Switchover back:**
```text
DGMGRL> SWITCHOVER TO PRIM;
```

> ✅ **Active Data Guard preserves state after SWITCHOVER TO PRIM.** With a properly executed `create_standby_broker.sh` (or manual Active DG section in docs/06):
> - `srvctl modify database -db STBY -startoption "READ ONLY"` → after `STARTUP` Oracle Restart opens in READ ONLY by itself,
> - `ALTER PLUGGABLE DATABASE ALL SAVE STATE` → PDBs return to `READ ONLY` after every STARTUP,
>
> so after `SWITCHOVER TO PRIM` the STBY database (as the new standby) opens immediately in `READ ONLY WITH APPLY` — without manual `STARTUP MOUNT` or manual `OPEN READ ONLY`.
>
> ⚠ **Fallback (section 0.3)** — required only if the broker still asks:
> ```
> Please complete the following steps to finish switchover:
>   start up instance "STBY" of database "stby"
> ```
> Then see section 0.3 (APPLY-OFF → OPEN RO + SAVE STATE → APPLY-ON). This is rare — typically after a manual `STARTUP NOMOUNT` or when someone stopped the DB before save_state was applied.

### Verification
- `SHOW CONFIGURATION` → `SUCCESS` and `PRIM = Primary database`
- `app_user.test_log` contains continuous entries with no gaps (`SELECT COUNT(*) FROM app_user.test_log` grows monotonically)
- Apply lag = 0

### Expected duration
| Direction | Switchover | App downtime (Oracle Restart configured) | Downtime (manual fallback) |
|----------|-----------|---------------------------------------------------|----------------------------|
| PRIM → STBY (on stby01) | 15–30 s (broker) | **~5–15 s** (Oracle Restart auto-starts service) | ~60 s (with `tac_service_resume.sh`) |
| STBY → PRIM (on prim01/02) | 15–30 s (broker) | **~5–15 s** (Grid CRS auto-start) | n/a (CRS always runs) |

**"Oracle Restart configured" precondition:** `setup_tac_services_stby.sh` was executed (or manual Step 1.5 from docs/08) — verify in pre-flight item 8.

---

## Scenario 2 — Unplanned failover with FSFO (kill primary)

### Goal
Demonstrate an **automatic** failover performed by the Observer after a Primary outage, without human intervention.

### Steps

**1. Verify FSFO is "armed" (from `infra01`):**
```bash
ssh oracle@infra01 "dgmgrl -silent /@PRIM_ADMIN 'SHOW FAST_START FAILOVER'" | tr '\n' ' ' | \
   grep -oE "Threshold:[[:space:]]*[0-9]+|Target:[[:space:]]*\w+|Observer:[[:space:]]*\w+"
# Threshold: 30
# Target: STBY
# Observer: obs_ext

ssh oracle@infra01 'sqlplus -s /@PRIM_ADMIN as sysdba <<EOF
SELECT fs_failover_status FROM v$database;
EXIT
EOF'
# SYNCHRONIZED   ← ready to failover
```

**2. Run `TestHarness` in the background on `client01`** (helper from 0.4).

**3. Mark the start time, kill both PRIM instances:**
```bash
date
# Tue Apr 23 16:00:00 UTC 2026

# Fastest way — shutdown abort both instances in parallel.
ssh oracle@prim01 'sqlplus -s / as sysdba <<EOF
SHUTDOWN ABORT
EXIT
EOF' &
ssh oracle@prim02 'sqlplus -s / as sysdba <<EOF
SHUTDOWN ABORT
EXIT
EOF' &
wait

# "Harder" alternative — full CRS stop on both nodes
# (also stops listeners/ASM — wider scope than shutdown abort):
# ssh root@prim01 sudo /u01/app/23.26/grid/bin/crsctl stop crs -f
# ssh root@prim02 sudo /u01/app/23.26/grid/bin/crsctl stop crs -f
```

**4. Watch the Observer log — expected flow:**
```bash
ssh oracle@infra01 "tail -f /var/log/oracle/obs_ext/obs_ext.log"
```
```
[W000 ...] Unable to connect to primary database
[W000 ...] Primary has no observer
[W000 ...] Threshold not reached; observer retry 1/3
[W000 ...] Observer retry 2/3, delay 10 seconds
[W000 ...] Threshold reached; initiating failover                ← ~30 s after kill
[W000 ...] Failover to STBY begun
[W000 ...] Failover succeeded; new primary is STBY               ← ~30–45 s
[W000 ...] Old primary needs to be reinstated
```

**5. Measure the end-to-end time:**
```bash
ssh oracle@infra01 'sqlplus -s /@STBY_ADMIN as sysdba <<EOF
SELECT database_role FROM v$database;
EXIT
EOF'
# DATABASE_ROLE
# PRIMARY

date
# Tue Apr 23 16:00:42 UTC 2026     ← ~42 s after shutdown abort
```

**6. Check the service on the new primary (Oracle Restart should start it by itself):**
```bash
# Expected state: Oracle Restart on stby01 started the service automatically
# (if docs/08 Step 1.5 / setup_tac_services_stby.sh was executed).
ssh oracle@stby01 ". ~/.bash_profile && srvctl status service -db STBY -service MYAPP_TAC"
# Service MYAPP_TAC is running on database STBY    ← TAC replay client will work

# Fallback (FIX-095) — ONLY if the above shows "is not running":
ssh oracle@stby01 ". ~/.bash_profile && bash /tmp/scripts/tac_service_resume.sh"
```

**7. In `TestHarness` you will see:**
```
[67] SUCCESS: PRIM2  SID=456  rows=1                  ← last before the outage
[68] RECOVERABLE (TAC replay/failover): 3113 - ORA-03113: end-of-file
[69] RECOVERABLE (TAC replay/failover): 17008 - Closed Connection
[70] SUCCESS: STBY  SID=234  rows=1                   ← first after failover (~60 s)
```

### Verification
- End-to-end broker failover: **30–45 s**
- Total client downtime with manual `tac_service_resume.sh`: **~60 s**
- **0 lost transactions** (commit_outcome + replay)
- `v$database.database_role` on STBY = `PRIMARY`
- Broker configuration = `SUCCESS`
- `SELECT COUNT(*) FROM app_user.test_log` continuous (every `loop=N` recorded)

### Reinstate the old Primary

```bash
# 1. Boot prim01/prim02 (if they were powered off — power on; if only shutdown abort — skip this line)
# 2. CRS on both nodes
ssh root@prim01 '/u01/app/23.26/grid/bin/crsctl start crs'
ssh root@prim02 '/u01/app/23.26/grid/bin/crsctl start crs'
sleep 120

# 3. Broker auto-reinstate (Flashback) — from infra01
ssh oracle@infra01
dgmgrl /@STBY_ADMIN
```
```text
DGMGRL> SHOW CONFIGURATION;
   PRIM - Physical standby database (reinstate required)

# After 60–120 s:
DGMGRL> SHOW CONFIGURATION;
   Configuration Status: SUCCESS
   PRIM - Physical standby database     ← reinstated
```

Optionally switchover back to the original primary:
```text
DGMGRL> SWITCHOVER TO PRIM;
```
(note FIX-094 — section 0.3, if the broker asks for STARTUP MOUNT + OPEN RO).

---

## Scenario 3 — TAC replay during a transaction (kill server process)

### Goal
Demonstrate that TAC with `session_state=DYNAMIC`, `commit_outcome=TRUE`, `failover_restore=LEVEL1` **automatically replays** a long-running transaction when the server process is killed mid-flight.

### Steps

**1. Temporary modification of `TestHarness.java` for a batch transaction:**

Change the main loop: instead of a single INSERT/COMMIT — 50× INSERT with a 1-second sleep, one COMMIT at the end (transaction length ~50 s):

```java
try (Connection conn = pds.getConnection()) {
    conn.setAutoCommit(false);   // F-09 — UCP 23.x default=true without setAutoCommit would give ORA-17273
    for (int i = 0; i < 50; i++) {
        try (PreparedStatement ps = conn.prepareStatement(
                "INSERT INTO app_user.test_log (instance, session_id, message) VALUES (?, ?, ?)")) {
            ps.setString(1, "batch-" + i);
            ps.setInt(2, (int)loop);
            ps.setString(3, "Batch entry " + i);
            ps.executeUpdate();
        }
        Thread.sleep(1000);
    }
    conn.commit();
    System.out.println("[" + loop + "] BATCH COMMITTED 50 rows");
}
```

Recompile and start:
```bash
ssh oracle@client01
cd /opt/lab/src
javac -cp "/opt/lab/jars/*" TestHarness.java
java --add-opens=java.base/java.lang=ALL-UNNAMED \
     --add-opens=java.base/java.util=ALL-UNNAMED \
     --add-opens=java.base/jdk.internal.misc=ALL-UNNAMED \
     --add-opens=java.base/sun.nio.ch=ALL-UNNAMED \
     -cp '/opt/lab/jars/*:.' TestHarness
```

**2. While the batch is running — kill the client's server process:**

Find the right SPID (server foreground bound to the JDBC session via the `MYAPP_TAC` service):
```bash
ssh oracle@prim01 ". ~/.bash_profile && sqlplus -s / as sysdba <<EOF
SET PAGESIZE 50 LINESIZE 200
COL spid     FORMAT A10
COL program  FORMAT A30
COL sid_ser  FORMAT A14
SELECT s.sid || ',' || s.serial# AS sid_ser, s.program, p.spid, s.service_name
FROM   gv\$session s JOIN gv\$process p ON s.paddr = p.addr
WHERE  s.service_name LIKE 'myapp_tac%'
   AND s.program LIKE 'JDBC%';
EXIT
EOF"
# Pick a SPID from the output and kill that specific process:
ssh oracle@prim01 "kill -9 <SPID>"
```

> 💡 **Why a specific SPID, not SMON/PMON:** killing a BACKGROUND process (PMON/SMON/LGWR) takes down the whole instance — you would see a reconnect to the other RAC node, not a clean TAC replay. The **server foreground process** (marked `(LOCAL=NO)`) bound to a specific JDBC session gives a clean replay demonstration.

**3. Expected `TestHarness` output:**
```
Batch 22 inserted...
Batch 23 inserted...
Batch 24 inserted...
[loop=N] RECOVERABLE (TAC replay/failover): 3113 - ORA-03113: end-of-file on communication channel
   (Application Continuity replayed 24 statements successfully)
Batch 25 inserted...
Batch 26 inserted...
...
[loop=N] BATCH COMMITTED 50 rows
```

Oracle JDBC TAC stored the **LTXID** before each INSERT, detected the disconnect (server proc kill = TCP RST), automatically opened a new session (on a different RAC instance after the FAN event) and **replayed** 24 INSERTs from the last committed point (`failover_restore=LEVEL1`), continuing from where it had stopped.

### Verification
**No duplicates in `test_log`:**
```sql
SELECT COUNT(*) FROM app_user.test_log WHERE session_id = <loop_no>;
-- 50 (exactly, NOT 74 = 24+50)
```
**No exception to the end user** — TestHarness caught `SQLRecoverableException` (in F-09 a separate handler), TAC performed the replay itself, transaction committed.

---

## Scenario 4 — Apply lag exceeded (FSFO blocked, Zero Data Loss)

### Goal
Demonstrate that when standby apply lag exceeds `FastStartFailoverLagLimit` (in our configuration = 0), FSFO **does NOT** perform an automatic failover — protecting against split-brain and data loss.

### Steps

**1. Check apply lag (should be 0):**
```bash
ssh oracle@infra01 'sqlplus -s /@PRIM_ADMIN as sysdba <<EOF
SELECT name, value FROM v$dataguard_stats;
EXIT
EOF'
# apply lag       0 00:00:00
```

**2. Stop MRP on STBY (from `infra01`):**
```bash
ssh oracle@infra01 'sqlplus -s /@STBY_ADMIN as sysdba <<EOF
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
EXIT
EOF'
```

**3. On PRIM force archiving + redo load:**
```bash
ssh oracle@prim01 'sqlplus -s / as sysdba <<EOF
BEGIN
    FOR i IN 1..10 LOOP
        EXECUTE IMMEDIATE '"'"'ALTER SYSTEM SWITCH LOGFILE'"'"';
        DBMS_SESSION.SLEEP(5);
    END LOOP;
END;
/
EXIT
EOF'
```

**4. Apply lag grows — Observer reports FSFO blocked:**
```bash
ssh oracle@infra01 "tail -f /var/log/oracle/obs_ext/obs_ext.log"
```
```
[W000 ...] Standby STBY is 45 seconds behind primary
[W000 ...] FSFO is not ready to failover — standby not synchronized
```

**5. Try to force a primary outage — Observer will NOT perform failover:**
```bash
ssh oracle@infra01 "dgmgrl -silent /@PRIM_ADMIN 'SHOW CONFIGURATION'"
# FS Failover Status: NOT SYNCHRONIZED   ← gating

# Outage simulation (in parallel):
ssh oracle@prim01 'sqlplus -s / as sysdba <<<"SHUTDOWN ABORT"' &
ssh oracle@prim02 'sqlplus -s / as sysdba <<<"SHUTDOWN ABORT"' &
wait

# Observer will print in the log:
#   "Threshold reached but apply lag exceeds LagLimit - failover blocked"
# = the mechanism preserved integrity, did not sacrifice data in the name of availability.
```

**6. Resume apply, FSFO returns to SYNCHRONIZED:**
```bash
# First boot prim01/02 back up.
ssh root@prim01 '/u01/app/23.26/grid/bin/crsctl start crs'
ssh root@prim02 '/u01/app/23.26/grid/bin/crsctl start crs'
sleep 120

ssh oracle@infra01 'sqlplus -s /@STBY_ADMIN as sysdba <<EOF
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT;
EXIT
EOF'

# After a moment
ssh oracle@infra01 'sqlplus -s /@PRIM_ADMIN as sysdba <<EOF
SELECT fs_failover_status FROM v$database;
EXIT
EOF'
# SYNCHRONIZED
```

> 💡 **FSFO modes (F-22):**
> - `LagLimit=0` + Protection Mode `MaxAvailability` (SYNC) = **Zero Data Loss Mode**. Failover is blocked on any apply lag > 0.
> - `LagLimit=30` + Protection Mode `MaxPerformance` (ASYNC) = **Potential Data Loss Mode**. Failover accepts up to 30 s of redo loss. Recommended when the link to standby is slow and SYNC would slow down commit on primary.
> - The LAB configuration uses **Zero Data Loss Mode** — Scenario 4 demonstrates the consequence of that decision.

---

## Scenario 5 — Master Observer outage (multi-Observer redundancy)

### Goal
Verify that an `infra01` outage (Master Observer `obs_ext`) **does not disable** the FSFO mechanism — a Backup Observer (`obs_dc` on prim01 or `obs_dr` on stby01) automatically takes over the Active role.

### Prerequisites
Multi-Observer deployed per `07_FSFO_Observers.md` section 6:
```bash
dgmgrl /@PRIM_ADMIN "SHOW OBSERVERS;"
# Master + 2 Backup
```

### Steps

**1. Stop the Master Observer:**
```bash
ssh root@infra01 "systemctl stop dgmgrl-observer-obs_ext"
```

**2. Watch the promote (from prim01 or stby01, e.g.):**
```bash
for i in 1 2 3 4 5 6; do
    ssh oracle@prim01 ". ~/.bash_profile && dgmgrl -silent /@PRIM_ADMIN 'SHOW OBSERVERS'" | grep -E "Master|Backup"
    sleep 10
done
# Within 10–60 s you see: one of the Backups changes status to Master.
```

**3. FSFO readiness verification:**
```bash
ssh oracle@prim01 ". ~/.bash_profile && dgmgrl -silent /@PRIM_ADMIN 'SHOW FAST_START FAILOVER'"
# Fast-Start Failover: ENABLED   ← system still armed
```

**4. (optional) Trigger a failover with the Master Observer killed:**

Repeat Scenario 2 steps 3–6, but **without restarting obs_ext**. The Backup Observer performs the failover and `tac_service_resume.sh` on the new primary must be run the same way as in Scenario 2.

**5. Restore Master:**
```bash
ssh root@infra01 "systemctl start dgmgrl-observer-obs_ext"
ssh oracle@infra01 "dgmgrl -silent /@PRIM_ADMIN 'SHOW OBSERVERS'"
# obs_ext returns as Backup; the current Active stays active until it dies.
```

### Verification
- Promote Backup → Master in < 60 s.
- `SHOW FAST_START FAILOVER` remains `ENABLED` throughout.
- For scenario 5.4 (failover with obs_ext down): RTO + client downtime as in Scenario 2 (`~60 s`).

---

## Scenario 6 — Readiness validation (`validate_env.sh`)

### Goal
Use the `validate_env.sh` script to comprehensively validate the configuration **before** scenarios 1–5 and **after** each of them (regression detection in the environment).

### Steps

**1. Pre-flight check (before the scenarios):**
```bash
ssh oracle@prim01 "bash /tmp/scripts/validate_env.sh --full"
```
Expected: all 10 sections PASS, exit code 0.

**2. Full TAC validation (additionally, at the SQL level):**
```bash
ssh oracle@prim01 ". ~/.bash_profile && sqlplus -s / as sysdba @/tmp/sql/tac_full_readiness_26ai.sql > /tmp/tac_readiness.log"
grep -E "PASS|FAIL|WARN" /tmp/tac_readiness.log | sort | uniq -c | sort -rn
# Should be: 0 FAIL, individual WARNs are acceptable (e.g. retention_timeout < 86400 - reco only).
```

**3. After failover (Scenario 2) — check whether the service is complete on the new primary:**
```bash
ssh oracle@stby01 ". ~/.bash_profile && sqlplus -s / as sysdba @/tmp/sql/tac_full_readiness_26ai.sql" | \
    grep -E "failover_restore|commit_outcome|session_state_consistency"
# All PASS = environment after failover ready for replay.
```

**4. Monitor replay during Scenario 3 tests:**
```bash
# In a separate terminal, on primary:
ssh oracle@prim01 ". ~/.bash_profile && sqlplus -s / as sysdba @/tmp/sql/tac_replay_monitor_26ai.sql"
# Shows: gv$replay_context (per-context metrics), gv$session.failed_over=YES count.
```

### Verification
- `validate_env.sh` exit code 0 (zero FAIL).
- `tac_full_readiness_26ai.sql` report: `failover_restore=LEVEL1` (PASS), `commit_outcome` (PASS), `session_state_consistency=DYNAMIC` (PASS), `aq_ha_notifications=YES` (PASS).
- `tac_replay_monitor_26ai.sql` after Scenario 3 shows >= 1 `failed_over=YES` session.

---

## Summary — checklist after all tests

| # | Scenario | Expected result | RTO/downtime (Oracle Restart cfg.) | Post-test verification |
|---|-----------|-------------------|--------------------------------------|---------------------|
| 1 | Switchover PRIM→STBY→PRIM | broker SUCCESS, `test_log` continuous | **~5–15 s** in both directions (CRS auto-start) | `SHOW CONFIGURATION` SUCCESS |
| 2 | Unplanned failover (FSFO) | new primary STBY in 30–45 s, replay OK | **~30–45 s** (broker + Oracle Restart auto-start) | `database_role=PRIMARY` on STBY, broker SUCCESS |
| 3 | TAC replay (kill server proc) | `app_user.test_log` has exactly 50 rows per batch (no duplicates) | none (client sees no error) | `tac_replay_monitor_26ai.sql` shows failed_over |
| 4 | Apply lag exceeded | FSFO blocked, `NOT SYNCHRONIZED`, database does not become primary after outage | manual recovery | `fs_failover_status=SYNCHRONIZED` after MRP resume |
| 5 | Master Observer outage | Backup promoted in 10–60 s, FSFO ENABLED | none | `SHOW OBSERVERS` shows Master+Backup |
| 6 | Readiness validation | `validate_env.sh` exit 0, TAC readiness PASS | n/a | all sections PASS |

### Recommended one-shot "smoke test" sequence

```bash
# 1. Pre-flight
ssh oracle@prim01 "bash /tmp/scripts/validate_env.sh --full"          # exit 0

# 2. TestHarness in the background
ssh oracle@client01 "cd /opt/lab/src && /opt/lab/run_testharness.sh &"

# 3. Scenario 1 + reset
# (run dgmgrl SWITCHOVER + tac_service_resume + SWITCHOVER back + 0.3 fix)

# 4. Scenario 2 (the most important demo)
# (shutdown abort + watch the log + tac_service_resume + reinstate)

# 5. Scenario 3 (TAC replay with modified TestHarness)

# 6. Scenario 5 (multi-Observer)

# 7. Final validation
ssh oracle@prim01 "sqlplus / as sysdba @/tmp/sql/tac_full_readiness_26ai.sql > /tmp/final.log"
ssh oracle@prim01 "grep -c FAIL /tmp/final.log"   # 0 = pass
```

After passing all 6 scenarios, the environment is documented as preserving **Zero Data Loss + Application Transparency** under failure conditions. This is full proof of meeting Oracle 26ai Maximum Availability Architecture (MAA).

---

## Next steps / Related documents

- `10_Performance_Tuning.md` — performance measurement: DBCA time, fio IOPS, time drift count.
- `../scripts/tac_service_resume.sh` — post-failover helper (sections 1.3, 2.6).
- `../scripts/validate_env.sh` — readiness validation (sections 0.1, 6.1).
- `../sql/tac_full_readiness_26ai.sql` — detailed SQL audit.
- `../sql/tac_replay_monitor_26ai.sql` — runtime replay monitoring.
