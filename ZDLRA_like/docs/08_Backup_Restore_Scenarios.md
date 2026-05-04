# 🧪 08 — Backup / Restore Scenarios (Sprint 2 + 3)

[![Sprint](https://img.shields.io/badge/Sprint-2%20%2B%203-blue)]()
[![Scenarios](https://img.shields.io/badge/Scenarios-8-success)]()
[![Type](https://img.shields.io/badge/Type-Demo_%2F_Validation-orange)]()
[![Pattern](https://img.shields.io/badge/Pattern-Diagnose%20→%20Action%20→%20Verify-purple)]()

> 🎯 8 demo backup/restore scenarios showcasing the full capabilities of the Recovery Appliance LAB.

## 📋 Scenario list

| ID | Title | Sprint | Scripts |
|---|---|---|---|
| [B-1](#b-1) | Basic catalog cycle: REGISTER -> FULL -> CROSSCHECK -> LIST | 2 | rman_full_backup.sh, rman_crosscheck.sh |
| [B-2](#b-2) | Weekly cycle: L0 + L1 + arch every 15 min | 2 | rman_full_backup.sh, rman_incremental_l1.sh, rman_archivelog_only.sh |
| [B-3](#b-3) | Incremental Merge / Virtual Full Backup | 3 | zdlra_sim_setup.sh |
| [B-4](#b-4) | PITR after DROP TABLE in a PDB | 2 | rman_restore_pitr.sh |
| [B-5](#b-5) | Online tablespace recovery | 2 | rman_restore_tablespace.sh |
| [B-6](#b-6) | Loss of CONTROLFILE + SPFILE -> autobackup | 2 | rman_restore_controlfile.sh |
| [B-7](#b-7) | Rebuild STBY01 from backup (DUPLICATE FROM BACKUPSET) | 3 | (DGMGRL + RMAN) |
| [B-8](#b-8) | Test environment refresh via DUPLICATE | 3 | rman_duplicate_for_test.sh |

---

## 📋 Common pre-checks (before any scenario)

Most scenarios assume Sprint 1 + Sprint 2 setup is complete. Verify once before the first session:

```bash
# 1) PRIM registered in catalog (Sprint 1 step 3a)
ssh oracle@prim01 'bash -lc "sqlplus -S \"rman_cat/\${LAB_PASS}@rcat01:1521/RCATPDB\" <<<\"SELECT name, dbid FROM rc_database;\""'
# Expected: PRIM 229119773 (or your LAB DBID)

# 2) Persistent RMAN config active (Sprint 2 — 9 CONFIGURE)
ssh oracle@prim01 'rman target / catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB" <<<"SHOW ALL;" 2>/dev/null | grep -c CONFIGURE'
# Expected: >= 9

# 3) First FULL backup done (needed as baseline for B-3..B-8)
ssh oracle@prim01 'ls -lh /mnt/rman_bck/full/ | head -10'
# Expected: backupset files bp_* or df_*

# 4) SSH equivalency rcat01 ↔ prim01 / prim02 / stby01 (after ssh_setup.sh full mesh)
ssh oracle@rcat01 'ssh -o PasswordAuthentication=no oracle@prim01 hostname'
# Expected: prim01 (no password prompt)

# 5) /mnt/rman_bck mounted on prim01
ssh oracle@prim01 'mount | grep rman_bck'
# Expected: vboxsf from D:\_RMAN_BCK_from_Linux_

# 6) LAB_PASS in /root/.lab_secrets on hosts where scripts run
ssh root@prim01 'cat /root/.lab_secrets | grep -c LAB_PASS'
# Expected: 1
```

> ⚠️ **Lessons learned to remember (from iter.12):** [#20](#troubleshooting) RMAN: `#` not `--` in comments (sql + bash heredocs). [#21](#troubleshooting) `GRANT EXECUTE ON SYS.DBMS_LOCK TO rman_cat`. [#22](#troubleshooting) `RC_BACKUP_SET` in 26ai without bytes — JOIN to `RC_BACKUP_PIECE`. [#24](#troubleshooting) `set -u` + `source ~/.bash_profile` = silent crash in scripts.

---

## <a id="b-1"></a>🔹 B-1: Full RMAN catalog cycle

**Goal:** Demonstrate the basic workflow: REGISTER -> FULL backup -> CROSSCHECK -> LIST.

### Steps

```bash
# On prim01 as oracle (assumes catalog ready from Sprint 1)

# 1) Check catalog status
sqlplus rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB <<<'SELECT name, dbid FROM rc_database;'
# Expected: PRIM is visible

# 2) FULL backup (up to 30 min)
bash /tmp/scripts/rman_full_backup.sh

# 3) Crosscheck + cleanup
bash /tmp/scripts/rman_crosscheck.sh

# 4) List backups in the catalog
rman target / catalog rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB <<<'LIST BACKUP SUMMARY;'
```

### 📝 Manual RMAN commands (alternative to scripts)

No wrapper — raw commands to paste after `rman target / catalog ...`:

```rman
# FULL L0 + ARCHIVELOG (instead of rman_full_backup.sh)
BACKUP INCREMENTAL LEVEL 0 AS COMPRESSED BACKUPSET TAG 'manual_b1' DATABASE PLUS ARCHIVELOG;

# Crosscheck + cleanup (instead of rman_crosscheck.sh)
CROSSCHECK BACKUP;
CROSSCHECK ARCHIVELOG ALL;
DELETE NOPROMPT EXPIRED BACKUP;
DELETE NOPROMPT EXPIRED ARCHIVELOG ALL;
DELETE NOPROMPT OBSOLETE;

# List
LIST BACKUP SUMMARY;
REPORT SCHEMA;
EXIT
```

### Expected results

- ✅ FULL backup completes without errors
- ✅ /mnt/rman_bck/full/ contains backupset files
- ✅ LIST BACKUP shows records with TAG=`weekly_l0_YYYYMMDD`
- ✅ In `RC_BACKUP_SET`: type `I lvl=0` (database) + `L` (archivelog) + `D` (controlfile autobackup) — **all STATUS=A** (lesson #22)

---

## <a id="b-2"></a>🔹 B-2: Weekly backup cycle

**Goal:** Simulate a 7-day cycle: Sunday L0 + Mon-Sat L1 + arch every 15 min.

### Steps — quick demo (1h instead of 7 days)

```bash
# We modify the cron schedule for the demo (temporarily):
# instead of '0 2 * * 0' use 'NOW' for a single execution

# 1) FULL L0 (one-off)
bash /tmp/scripts/rman_full_backup.sh

# 2) Force rotation of 5 archlogs so there is something to back up
sqlplus / as sysdba <<'SQL'
ALTER SYSTEM SWITCH LOGFILE; ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM SWITCH LOGFILE; ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM SWITCH LOGFILE;
SQL

# 3) ARCHIVELOG backup
bash /tmp/scripts/rman_archivelog_only.sh

# 4) "Day 1" simulation — L1 incremental
bash /tmp/scripts/rman_incremental_l1.sh

# 5) Health check
sqlplus rman_cat/...@rcat01:1521/RCATPDB @/tmp/sql/20_health_checks.sql
```

### Expected results

- ✅ 3 backup types visible (full, incr, arch) in `LIST BACKUP SUMMARY`
- ✅ Success ratio in health_check #6 = 100%
- ✅ Size of /mnt/rman_bck can be measured per type

---

## <a id="b-3"></a>🔹 B-3: Incremental Merge (Virtual Full Backup)

**Goal:** Demonstrate the ZDLRA-like incremental-forever pattern.

### Steps

```bash
# On prim01 as oracle

# 1) Init (one-off)
bash /tmp/scripts/zdlra_sim_setup.sh --init

# 2) "Day 2" simulation — run the merge
# Force some changes in the database (UPDATE on some table)
sqlplus / as sysdba <<'SQL'
ALTER SESSION SET CONTAINER=APPPDB;
INSERT INTO test_table VALUES (...) WHERE rownum <= 1000;
COMMIT;
SQL

bash /tmp/scripts/zdlra_sim_setup.sh --merge

# 3) Status
bash /tmp/scripts/zdlra_sim_setup.sh --status

# 4) Validate (verifying that the image copy is current)
rman target / catalog rman_cat/...@rcat01:1521/RCATPDB <<'RMAN'
LIST COPY OF DATABASE TAG 'incr_merge';
RESTORE DATABASE PREVIEW SUMMARY;
RMAN
```

### 📝 Manual RMAN commands

> 💡 **The full virtual full backup pattern in manual form is described in [doc 07 section "Manual RMAN commands"](07_ZDLRA_Like_Simulation.md#-manual-rman-commands-copypaste-no-wrapper).** Short version here:

```rman
# Initial L0 IMAGE COPY (one-off, instead of --init):
BACKUP INCREMENTAL LEVEL 0 AS COPY TAG 'incr_merge' DATABASE
  FORMAT '/mnt/rman_bck/incr_merge/df_%d_%U';

# Daily merge cycle (instead of --merge):
RECOVER COPY OF DATABASE WITH TAG 'incr_merge';
BACKUP INCREMENTAL LEVEL 1 FOR RECOVER OF COPY WITH TAG 'incr_merge'
  DATABASE FORMAT '/mnt/rman_bck/incr_merge/incr_%d_%U';

# Validate
LIST COPY OF DATABASE TAG 'incr_merge';
RESTORE DATABASE PREVIEW SUMMARY;
```

### Expected results

- ✅ After init: image copy is the size of the database (~50 GB uncompressed)
- ✅ After merge: image copy has a new timestamp (like a fresh L0)
- ✅ RESTORE PREVIEW shows the image copy as the PRIMARY source

---

## <a id="b-4"></a>🔹 B-4: PITR after DROP TABLE

**Goal:** "Classic scenario" — a user accidentally dropped a table, recovery to the SCN before.

### Steps

```bash
# 1) Pre-state: note the SCN before DROP
sqlplus / as sysdba <<'SQL'
ALTER SESSION SET CONTAINER=APPPDB;
SELECT current_scn FROM v$database;  -- e.g. 1234567
EXIT
SQL
SCN_BEFORE=1234567  # SAVE THIS

# 2) Backup state before
bash /tmp/scripts/rman_full_backup.sh
sqlplus / as sysdba <<'SQL'
ALTER SESSION SET CONTAINER=APPPDB;
ALTER SYSTEM SWITCH LOGFILE; ALTER SYSTEM SWITCH LOGFILE;
SQL
bash /tmp/scripts/rman_archivelog_only.sh

# 3) "Accident" — DROP TABLE (as user, not sys!)
sqlplus app_user/...@prim:1521/APPPDB <<'SQL'
DROP TABLE critical_data;
SQL

# 4) PITR to SCN_BEFORE
bash /tmp/scripts/rman_restore_pitr.sh --pdb APPPDB --scn $SCN_BEFORE

# 5) Validation
sqlplus / as sysdba <<'SQL'
ALTER SESSION SET CONTAINER=APPPDB;
SELECT COUNT(*) FROM critical_data;  -- should return data
SQL
```

### 📝 Manual RMAN commands (single-PDB PITR)

```rman
# Step 1: Close the PDB (but not the whole instance!)
ALTER PLUGGABLE DATABASE APPPDB CLOSE IMMEDIATE;

# Step 2: PITR to SCN_BEFORE (e.g. 1234567)
RUN {
  SET UNTIL SCN 1234567;
  RESTORE PLUGGABLE DATABASE APPPDB;
  RECOVER PLUGGABLE DATABASE APPPDB;
}

# Step 3: Open RESETLOGS (required after PITR)
ALTER PLUGGABLE DATABASE APPPDB OPEN RESETLOGS;
```

> 💡 **Alternative timestamp form** (more intuitive):
> ```rman
> SET UNTIL TIME "TO_DATE('2026-05-04 14:30:00','YYYY-MM-DD HH24:MI:SS')";
> ```

> ⚠️ **Single-PDB PITR in 23ai/26ai** requires `BACKUP DATABASE INCLUDE CURRENT CONTROLFILE` (default in our `rman_full_backup.sh`). Without it the CDB has no snapshot controlfile for that PDB.

### Expected results

- ✅ Table `critical_data` exists after PITR
- ✅ Data up to SCN_BEFORE preserved
- ✅ All changes AFTER SCN_BEFORE lost (RESETLOGS)
- ✅ New `incarnation#` in `v$pdb_incarnation` (per-PDB resetlogs)

---

## <a id="b-5"></a>🔹 B-5: Online tablespace recovery

**Goal:** Show that a single tablespace can be recovered WITHOUT stopping the PDB.

### Steps

```bash
# 1) Simulate file damage (as root)
sudo dd if=/dev/zero of=/u02/oradata/PRIM/apppdb/users01.dbf bs=8192 count=10 conv=notrunc
# (the first 80 KB destroyed — block corruption)

# 2) Check the alert log — there should be ORA-1578 errors (corrupt block)
sudo tail -50 /u01/app/oracle/diag/rdbms/prim/PRIM1/trace/alert_PRIM1.log | grep -i corrupt

# 3) Tablespace recovery
bash /tmp/scripts/rman_restore_tablespace.sh --pdb APPPDB --ts USERS

# 4) Validation
sqlplus / as sysdba <<'SQL'
ALTER SESSION SET CONTAINER=APPPDB;
SELECT name, status FROM v$datafile WHERE name LIKE '%users01%';
-- STATUS=ONLINE
SQL
```

### Expected results

- ✅ Tablespace USERS is ONLINE again
- ✅ Other tablespaces were NOT affected
- ✅ APPPDB stayed open the whole time

---

## <a id="b-6"></a>🔹 B-6: Disaster recovery — loss of controlfile + spfile

**Goal:** Worst-case scenario — we lose both critical configuration files.

### Steps

```bash
# 1) Save the DBID (critical!)
DBID=$(sqlplus -S / as sysdba <<<'SET HEADING OFF FEEDBACK OFF; SELECT dbid FROM v$database;')
echo "DBID = $DBID"  # SAVE THIS

# 2) Simulate the loss
sqlplus / as sysdba <<'SQL'
SHUTDOWN ABORT;
EXIT
SQL
sudo rm /u02/oradata/PRIM/control01.ctl
sudo rm /u01/app/oracle/product/23.26/dbhome_1/dbs/spfilePRIM*.ora

# 3) Restore from autobackup
bash /tmp/scripts/rman_restore_controlfile.sh --dbid $DBID

# 4) Validation
sqlplus / as sysdba <<'SQL'
SELECT name, open_mode FROM v$database;
SELECT count(*) FROM v$datafile;
SQL
```

### 📝 Manual RMAN commands (worst-case scenario — full restore)

```rman
# Step 1: Connect without TARGET (CDB doesn't exist yet)
# from host: rman catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB"

SET DBID 229119773;   # substitute your DBID from $DBID

# Step 2: Startup nomount with restored spfile
STARTUP NOMOUNT FORCE;
RESTORE SPFILE FROM AUTOBACKUP;

# Step 3: Restart NOMOUNT with restored spfile
STARTUP FORCE NOMOUNT;
RESTORE CONTROLFILE FROM AUTOBACKUP;

# Step 4: Mount + restore + recover
ALTER DATABASE MOUNT;
RESTORE DATABASE;
RECOVER DATABASE;
ALTER DATABASE OPEN RESETLOGS;
```

> 💡 **Key to success:** you must know the DBID **before** the failure (`SELECT dbid FROM v$database`). Without DBID restore from autobackup is impossible. **Save the DBID after every structural change** (e.g. in `${HOME}/dbid.txt`).

> ⚠️ **Lesson #21:** the rman_cat user needs EXECUTE on DBMS_LOCK (pre-check in the common section above), otherwise RESTORE CONTROLFILE fails on the catalog connection.

### Expected results

- ✅ Database opened in RESETLOGS mode
- ✅ All datafiles visible
- ✅ New incarnation in v$database_incarnation
- ✅ `RC_DATABASE_INCARNATION` on rcat01 has a new entry with the latest open `RESETLOGS_TIME`

---

## <a id="b-7"></a>🔹 B-7: Rebuild STBY01 from backup

**Goal:** Show that when stby01 is completely lost, it can be rebuilt from the RMAN backup
(instead of Active Duplicate, which requires a network transfer from PRIM).

### Steps

```bash
# 1) Simulate catastrophic stby01 failure
ssh root@stby01 'systemctl stop oracle-rcat || true; rm -rf /u02/oradata/STBY/*'

# 2) On stby01: startup NOMOUNT with a dummy initfile
ssh oracle@stby01 << 'EOF'
cat > /tmp/init_dummy.ora <<INIT
db_name='STBY'
db_unique_name='STBY'
INIT
sqlplus / as sysdba <<SQL
STARTUP NOMOUNT PFILE='/tmp/init_dummy.ora';
EXIT
SQL
EOF

# 3) From prim01: DUPLICATE FOR STANDBY FROM BACKUPSET
ssh oracle@prim01 << 'EOF'
rman target / auxiliary sys/${LAB_PASS}@stby01:1521/STBY catalog rman_cat/...@rcat01:1521/RCATPDB <<RMAN
DUPLICATE TARGET DATABASE FOR STANDBY FROM BACKUPSET;
RMAN
EOF

# 4) Re-enable Data Guard
ssh oracle@stby01 'dgmgrl sys/...@stby <<<"ENABLE DATABASE STBY;"'

# 5) Validate apply
ssh oracle@stby01 'sqlplus / as sysdba <<<"SELECT process, status FROM v\$managed_standby;"'
```

### 📝 Manual RMAN commands (DUPLICATE FOR STANDBY)

```rman
# Connect from prim01: TARGET=PRIM, AUXILIARY=stby01 NOMOUNT, CATALOG=rcat01
# rman target / auxiliary "sys/${LAB_PASS}@stby01:1521/STBY" \
#                catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB"

DUPLICATE TARGET DATABASE FOR STANDBY
  FROM BACKUPSET
  DORECOVER
  NOFILENAMECHECK
  SPFILE
    SET db_unique_name='STBY'
    SET local_listener=''
    SET fal_server='PRIM'
    SET log_archive_dest_2='SERVICE=PRIM ASYNC NOAFFIRM VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE) DB_UNIQUE_NAME=PRIM';
```

> 💡 **`FROM BACKUPSET` vs Active Duplicate:** the difference is the data source. BACKUPSET reads from `/mnt/rman_bck/full/` (offline-friendly, no PRIM load). Active pulls block-by-block over the network from the live PRIM (online).

> ⚠️ **DORECOVER** is critical — without it the standby will be behind PRIM by the duration of DUPLICATE. DORECOVER applies archive logs up to the recovery point at the moment DUPLICATE was kicked off.

### Expected results

- ✅ stby01 rebuilt WITHOUT load on PRIM (Active Duplicate would pull data from PRIM live)
- ✅ Data Guard apply RESUMED
- ✅ Switchover test after rebuild works

### Difference vs Active Duplicate

| Method | I/O on PRIM | Time | Failure odds |
|---|---|---|---|
| Active Duplicate (existing) | high (50 GB read from PRIM) | slower | medium (network glitches) |
| Duplicate FROM BACKUPSET | none (read from /mnt/rman_bck) | faster | lower (offline-friendly) |

---

## <a id="b-8"></a>🔹 B-8: Test environment refresh

**Goal:** Real-world DBA use-case — every week we refresh the TEST environment from the latest PROD backup.

### Steps

```bash
# Pre-reqs:
# - Aux VM 'test01' (192.168.56.17, ORACLE_HOME empty)
# - test01:1521/TEST reachable

# 1) Aux VM startup NOMOUNT
ssh oracle@test01 << 'EOF'
sqlplus / as sysdba <<SQL
STARTUP NOMOUNT PFILE='/tmp/init_test.ora';
EXIT
SQL
EOF

# 2) DUPLICATE FROM BACKUPSET (PRIM -> TEST)
bash /tmp/scripts/rman_duplicate_for_test.sh \
    --aux test01:1521/TEST \
    --target_db PRIM \
    --new_name TEST

# 3) Validation
ssh oracle@test01 'sqlplus / as sysdba <<<"SELECT name, db_unique_name FROM v\$database;"'
# Expected: NAME=TEST, db_unique_name=TEST
```

### 📝 Manual RMAN commands (DUPLICATE TARGET = test refresh)

```rman
# Connect from prim01: TARGET=PRIM, AUXILIARY=test01 NOMOUNT, CATALOG=rcat01

DUPLICATE TARGET DATABASE TO TEST
  FROM BACKUPSET
  NOFILENAMECHECK
  SPFILE
    SET db_unique_name='TEST'
    SET db_name='TEST'
    SET log_archive_dest_2=''
    SET fal_server=''
    SET log_archive_dest_1='LOCATION=/u02/oradata/TEST/arch';
```

> 💡 **Difference vs B-7 (FOR STANDBY):** no `FOR STANDBY` + `DORECOVER` → RMAN creates a new database (new DBID, role=PRIMARY). Ideal for test/dev refresh.

### Expected results

- ✅ New TEST database opened
- ✅ Data schema identical to PRIM (as of the backup time)
- ✅ Periodic refresh possible (DELETE TEST + DUPLICATE)
- ✅ TEST has its own DBID (NOT the same as PRIM, unlike FOR STANDBY)

---

## 📊 Summary

After running all 8 scenarios we have a validated full backup/restore workflow:
- ✅ Backup cycle (B-1, B-2)
- ✅ Storage optimization (B-3)
- ✅ Logical recovery (B-4)
- ✅ Granular recovery (B-5)
- ✅ Disaster recovery (B-6)
- ✅ DG integration (B-7)
- ✅ Real-world DBA tasks (B-8)

This covers **80%** of typical scenarios that a real ZDLRA also supports.

## 🔮 Out of Scope: Zero RPO recovery (B-9 — optional)

The remaining **~20%** of real ZDLRA functionality is **Zero RPO recovery** — recovery to the last committed transaction *without* waiting for an archivelog switch. In this LAB this scenario is **NOT enabled** because it requires real-time redo to rcat01 (ORA-16009 — see [Lesson #29](07_ZDLRA_Like_Simulation.md#-lesson-29-real-time-redo-to-rcat01--architectural-limit)).

> 💡 **Possible extension:** building a physical standby of PRIM on rcat01 (Sprint 5 optional) unlocks DEST_3 + scenario **B-9 Zero RPO recovery**. Full step plan + RMAN DUPLICATE block + cost/benefit:
> [doc 07 section "Possible LAB extension"](07_ZDLRA_Like_Simulation.md#-possible-lab-extension-sprint-5-optional--physical-standby-of-prim-on-rcat01).
>
> **Decision:** documented but **not planned** — the practical workaround for ~15 min RPO (`rman_archivelog_only.sh` cron) suffices for the current LAB goals.

## <a id="troubleshooting"></a>🚧 Troubleshooting (lessons learned for scenarios)

The most common issues that may surface while running scenarios B-1..B-8. All were verified empirically during Iter.10-12 (2026-05-03/04).

| Problem | Resolution | Lesson |
|---|---|---|
| `RMAN-02001 unrecognized punctuation symbol "-"` | RMAN doesn't accept `--` as comment. Use `#` in `.sql` files AND in bash heredocs | #20 |
| `PLS-00201: identifier 'DBMS_LOCK' must be declared` | `GRANT EXECUTE ON SYS.DBMS_LOCK TO rman_cat` in PDB RCATPDB | #21 |
| `BACKUP DATABASE PLUS ARCHIVELOG` only backs up archivelogs, DB itself NOT | Lesson #21 (DBMS_LOCK) — catalog registration blocked, RMAN doesn't proceed to DATABASE phase | #21 |
| `RMAN-20002 target database already registered` | OK on REGISTER re-run. `UNREGISTER DATABASE x NOPROMPT` + REGISTER again, or skip (idempotent) | #16 |
| Script rman_*.sh shows nothing, log file empty | `set -u` + `source ~/.bash_profile` silent crash. Wrap source in `set +u; source ...; set -u` (v1.2 fix) | #24 |
| `bash /tmp/scripts/...` fails with `Permission denied` | `/tmp/scripts/` owned by root. Workaround: scp to `/tmp/` + sudo cp to `/tmp/scripts/` | #19 |
| `RC_BACKUP_SET` query fails with `OUTPUT_BYTES invalid identifier` | In 26ai `RC_BACKUP_SET` has no byte columns. JOIN `RC_BACKUP_PIECE` on `bs_key` | #22 |
| `RC_SITE` query fails with `DBID invalid identifier` | In 26ai `RC_SITE` has no DBID/DB_NAME. JOIN `RC_DATABASE` on `db_key` | #17 |
| `BACKUP_TYPE='D'` expected for FULL but got `'I' lvl=0` | In 26ai "FULL" = `INCREMENTAL_LEVEL=0`. Codes: D=Controlfile, I=Incremental, L=Archivelog | #22 |
| Script prompts repeatedly for SSH password | VM↔VM SSH equiv NOT configured. Run `bash /tmp/scripts/ssh_setup.sh` as root on prim01 | #18 |
| `tnsping rcat01_redo` returns "command not found" | In non-login SSH shell PATH is not set. Use `bash -lc 'tnsping ...'` | #13 |
| FSFO failover happened — PRIM/STBY roles reversed | Check `database_role` on both nodes. If stby01=PRIMARY and prim01=STANDBY: `dgmgrl 'SWITCHOVER TO PRIM'` before scenarios | (DG) |

## ⏭️ See also

- [09_DG_Integration.md](09_DG_Integration.md) — Backup ↔ DG integration details
- [10_Troubleshooting.md](10_Troubleshooting.md) — FAQ + known issues
