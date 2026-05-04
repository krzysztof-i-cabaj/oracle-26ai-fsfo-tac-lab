# 🔗 09 — DG Integration (Sprint 3)

[![Sprint](https://img.shields.io/badge/Sprint-3-blue)]()
[![Topic](https://img.shields.io/badge/Topic-Backup_↔_DG-purple)]()
[![Layer](https://img.shields.io/badge/MAA_Stack-Complete-success)]()
[![Pattern](https://img.shields.io/badge/Pattern-Switchover_Aware-orange)]()

> 🎯 How the Backup layer cooperates with the existing Data Guard (PRIM ↔ STBY01).

## 📋 Pre-checks (conditions for DG-aware scenarios)

Before starting any backup ↔ DG integration scenario (B-7 rebuild, switchover-aware backup, real-time redo to RA):

```bash
# 1) DG broker SUCCESS, roles consistent with naming convention
ssh infra01 "TNS_ADMIN=/etc/oracle/tns/obs_ext dgmgrl /@PRIM_ADMIN 'SHOW CONFIGURATION'"
# Expected: Configuration Status SUCCESS, prim01=primary, stby01=physical standby

# 2) Current PRIM role (verify no FSFO failover happened)
ssh oracle@prim01 'bash -lc "sqlplus -S / as sysdba <<<\"SET HEADING OFF FEEDBACK OFF; SELECT database_role FROM v\\\$database;\""'
# Expected: PRIMARY (if STANDBY → run switchover to PRIM before scenarios)

# 3) Observers active (if you use FSFO)
ssh infra01 'pgrep -af "dgmgrl.*observer" | wc -l'
# Expected: >= 1 (if FSFO MaxAvailability)

# 4) APPLY-ON on stby01
ssh infra01 "TNS_ADMIN=/etc/oracle/tns/obs_ext dgmgrl /@PRIM_ADMIN 'SHOW DATABASE STBY'" | grep -i 'apply state'
# Expected: Apply state: APPLY-ON (or Apply state: REDO_APPLY)

# 5) Sprint 1 + 2 setup (from doc 08 pre-checks)
# See: docs/08_Backup_Restore_Scenarios.md section 'Common pre-checks'
```

> ⚠️ **Lessons learned to remember:** [#17 RC_SITE without DBID](08_Backup_Restore_Scenarios.md#troubleshooting), [#21 DBMS_LOCK grant](08_Backup_Restore_Scenarios.md#troubleshooting). Full table: [doc 08 troubleshooting](08_Backup_Restore_Scenarios.md#troubleshooting).

## 🧩 Architecture: Backup in the presence of DG

```
┌──────────────────────────────────────────────────────────────────┐
│                      Data Guard Configuration                     │
├──────────────────────────────────────────────────────────────────┤
│   PRIMARY            STANDBY               OBSERVER(S)            │
│   PRIM (RAC 2-node)  STBY (Oracle Restart) obs_ext (infra01)      │
│                                            obs_dr (stby01)        │
│                                                                   │
│   Data Guard Broker   FSFO   TAC                                  │
└──────────────────────────────────────────────────────────────────┘
                ↓
┌──────────────────────────────────────────────────────────────────┐
│                     RMAN Recovery Catalog                         │
│   rcat01: rman_cat schema in PDB RCATPDB                          │
│                                                                   │
│   - Registers PRIM (dbid)                                         │
│   - STBY automatically known via DG broker integration            │
│   - Backups can be taken from PRIMARY or STANDBY                  │
└──────────────────────────────────────────────────────────────────┘
```

## ⚖️ Backup from PRIM or STBY?

### Option A: Backup from PRIMARY (current PRIM)

**Pros:**
- ✅ Easiest to configure (TARGET=/, current primary)
- ✅ Does not require a separate RMAN setup on STBY
- ✅ Standard pattern for smaller databases

**Cons:**
- ❌ Loads PRIM (I/O, CPU, network to /mnt/rman_bck)
- ❌ Under high production load — visible degradation
- ❌ After failover (PRIM -> STBY) the cron schedule must be adjusted

### Option B: Backup from PHYSICAL STANDBY

**Pros:**
- ✅ ZERO load on PRIM (critical in prod systems)
- ✅ STBY already has a complete copy of the data — it can do the backup
- ✅ Active DG (Open Read-Only) allows querying + backup

**Cons:**
- ❌ Requires extra RMAN configuration on STBY
- ❌ DBID is the same as PRIM — the catalog sees backups from STBY as if they came from PRIM

### LAB recommendation

In the LAB we choose **Option A (backup from PRIM)** for simplicity. In docs/06_Backup_Policy.md the cron is on prim01.

In production it is worth considering **Option B**, but it requires extra configuration that we do not show in the LAB.

## 🔄 What happens during switchover (PRIM <-> STBY)

### Before switchover

```
PRIM (db_unique_name=PRIM, role=PRIMARY)  - this is where we run backups
STBY (db_unique_name=STBY, role=PHYSICAL_STANDBY)  - apply only
```

### After switchover

```
PRIM (db_unique_name=PRIM, role=PHYSICAL_STANDBY)  - no longer primary!
STBY (db_unique_name=STBY, role=PRIMARY)  - the backup should now run here
```

**Problem:** the cron on "prim01" triggers the backup, but prim01 is no longer primary.
Solution: in the scripts we check the database role before running the backup.

```bash
# In rman_full_backup.sh we add a pre-check
ROLE=$(sqlplus -S / as sysdba <<<'SET HEADING OFF FEEDBACK OFF; SELECT database_role FROM v$database;')
if [[ "$ROLE" != *"PRIMARY"* ]]; then
    log "[skip] This host is not PRIMARY (role=$ROLE). Backup should run on the other site."
    exit 0
fi
```

**Better option**: cron on **both** hosts (prim01 and stby01), both with this pre-check.
The one that is currently PRIMARY runs the backup, the other one skips.

## 🛠️ B-7 deep dive: Rebuild STBY from backup

Scenario B-7 (from `08_Backup_Restore_Scenarios.md`) is a particularly important case
of Backup ↔ DG integration.

### When to use DUPLICATE FROM BACKUPSET instead of Active Duplicate?

| Situation | Active Duplicate | FROM BACKUPSET |
|---|---|---|
| STBY out-of-sync but functional | ✅ (online resync) | ❌ (overkill) |
| STBY broken — full rebuild | ⚠️ (loads PRIM live) | ✅ (preferred) |
| No PRIM<->STBY network temporarily | ❌ | ✅ (offline-friendly) |
| Very large database (TB+) | ❌ (network bottleneck) | ✅ (read from local disk) |

### Step sequence

#### 🚀 Method A — wrapper script (no wrapper yet — TODO)

> 💡 **Status:** a dedicated `rman_rebuild_standby.sh` wrapper does **not exist yet**. B-7 rebuild is performed manually for now (Method B below). This is intentional — rebuilding standby is a "DBA decision" operation, not cyclical. Manual control = awareness of every step. A wrapper can be added if rebuilds become frequent (e.g. test environments).

#### 🛠️ Method B — manual (step sequence)

```bash
# 1) Pre-state: STBY broken
ssh oracle@stby01
sqlplus / as sysdba <<<'SHUTDOWN ABORT;'

# 2) Wipe datafiles (simulation - or real disaster)
sudo rm -rf /u02/oradata/STBY/*

# 3) Startup NOMOUNT with a minimal initfile
cat > /tmp/init_stby_nomount.ora <<'INIT'
db_name='STBY'
db_unique_name='STBY'
INIT
sqlplus / as sysdba <<'SQL'
STARTUP NOMOUNT PFILE='/tmp/init_stby_nomount.ora';
SQL

# 4) From PRIM: DUPLICATE FOR STANDBY FROM BACKUPSET (manual RMAN below)
ssh oracle@prim01
```

#### 📝 Manual RMAN commands (DUPLICATE FOR STANDBY)

```bash
# Connect: TARGET=PRIM, AUXILIARY=stby01 NOMOUNT, CATALOG=rcat01
rman target / \
     auxiliary "sys/${LAB_PASS}@stby01:1521/STBY" \
     catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB"
```

```rman
DUPLICATE TARGET DATABASE FOR STANDBY
  FROM BACKUPSET
  DORECOVER
  NOFILENAMECHECK
  SPFILE
    SET db_unique_name='STBY'
    SET fal_server='PRIM'
    SET log_archive_config='DG_CONFIG=(PRIM,STBY)'
    SET log_archive_dest_2='SERVICE=PRIM ASYNC NOAFFIRM VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE) DB_UNIQUE_NAME=PRIM'
    SET standby_file_management='AUTO'
    SET dg_broker_start='TRUE';
```

> 💡 **Key SPFILE SET parameters:**
> - `db_unique_name='STBY'` — identifier for DG broker
> - `fal_server='PRIM'` — fetch archive logs source on gap recovery
> - `log_archive_config` — DG configuration list (must match on PRIM and STBY)
> - `log_archive_dest_2` — when STBY becomes PRIMARY (after switchover), redo goes to PRIM
> - `standby_file_management='AUTO'` — auto-create datafiles after `ADD DATAFILE` on PRIM
> - `dg_broker_start='TRUE'` — enables broker processes

```bash
# 5) Re-enable in DG broker (after DUPLICATE finishes)
ssh oracle@prim01 'dgmgrl /@PRIM_ADMIN'
```

```dgmgrl
ENABLE DATABASE STBY;
SHOW CONFIGURATION;
SHOW DATABASE STBY;

# Should show Status: SUCCESS, Apply Lag/Transport Lag = 0
```

```bash
# 6) Validate apply on stby01
ssh oracle@stby01 'sqlplus / as sysdba <<<"SELECT process, status, sequence# FROM v\$managed_standby ORDER BY 1;"'

# Expected processes:
# ARCH (multiple) - archive log fetcher
# MRP0           - Managed Recovery Process (apply)
# RFS            - Remote File Server (receive from PRIM)
```

### Critical settings after rebuild

```sql
-- On stby01 after DUPLICATE
ALTER SYSTEM SET STANDBY_FILE_MANAGEMENT=AUTO;
ALTER SYSTEM SET DG_BROKER_START=TRUE;
ALTER SYSTEM SET LOG_ARCHIVE_DEST_2='SERVICE=PRIM ASYNC ...';
```

## 🔌 Real-time redo from PRIM to RA (Sprint 3, ZDLRA-like)

This is the **third role** for rcat01 (besides catalog and appliance):

```
PRIM redo stream:
  LOG_ARCHIVE_DEST_1 = local (online redo files)
  LOG_ARCHIVE_DEST_2 = STBY (DG transport, SYNC AFFIRM for MAX_AVAILABILITY)
  LOG_ARCHIVE_DEST_3 = rcat01 (ZDLRA-like, ASYNC NOAFFIRM)
```

`LOG_ARCHIVE_DEST_3` gives rcat01 a redo stream independent of DG.

### Does it conflict with DG?

No. DG (DEST_2) and RA-redo (DEST_3) are independent:
- DEST_2 is SYNC AFFIRM for zero data loss on switchover
- DEST_3 is ASYNC NOAFFIRM for minimal overhead on PRIM
- Both are configured with `VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE)`
- After switchover (PRIM -> STBY), DEST_3 must be reconfigured on the new primary

## ⏭️ Related

- [07_ZDLRA_Like_Simulation.md](07_ZDLRA_Like_Simulation.md) — LOG_ARCHIVE_DEST_3 details
- [08_Backup_Restore_Scenarios.md#b-7](08_Backup_Restore_Scenarios.md#b-7) — scenario B-7
- [08_Backup_Restore_Scenarios.md#troubleshooting](08_Backup_Restore_Scenarios.md#troubleshooting) — full lessons-learned table for scenarios
- `../../docs/07_FSFO_Observery.md` — Data Guard Broker config (parent project)
- `../../docs/06_Data_Guard_Standby.md` — DG initial setup (parent project)
