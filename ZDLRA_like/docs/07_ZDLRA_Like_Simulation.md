# 🛡️ 07 — ZDLRA-Like Simulation (Sprint 3)

[![Sprint](https://img.shields.io/badge/Sprint-3-blue)]()
[![Concept](https://img.shields.io/badge/Concept-Virtual_Full_Backup-purple)]()
[![Real_ZDLRA](https://img.shields.io/badge/Real_ZDLRA-Closed_Source-red)]()
[![LAB](https://img.shields.io/badge/LAB-Plain_RMAN_%2B_DG-success)]()
[![RPO](https://img.shields.io/badge/RPO-near_zero-orange)]()

> 🎯 Simulation of the key features of **Zero Data Loss Recovery Appliance** in plain RMAN + Data Guard.
> Boundary: ZDLRA-like ≠ ZDLRA. We do not simulate block dedup or tape-out.

## 🧠 What is ZDLRA?

Oracle **Zero Data Loss Recovery Appliance** is a dedicated hardware device (Engineered System)
offering:
1. **Real-time redo transport** from target databases (RPO ~0)
2. **Virtual Full Backups** via incremental-forever architecture
3. **Block-level deduplication** in the storage layer (HW-accelerated)
4. **Tape-out integration** to Oracle Secure Backup or other libraries
5. **Centralized catalog** managing backups for hundreds of databases
6. **Cross-RA replication** (Active-Active for DR of the appliance itself)

ZDLRA is Oracle's purpose-built engineered system for backup. Closed-source HW + RA Software.

## 🔧 What we simulate in the LAB

| ZDLRA feature | LAB simulation | Script | Status |
|---|---|---|---|
| Real-time redo | `LOG_ARCHIVE_DEST_3 ASYNC NOAFFIRM` PRIM -> rcat01 | `zdlra_sim_setup.sh --init` | ⚠️ **architectural limit** — see lesson #29 below |
| Virtual Full Backup | `BACKUP INCREMENTAL LEVEL 1 FOR RECOVER OF COPY` + `RECOVER COPY OF DATABASE` | `zdlra_sim_setup.sh --merge` | ✅ |
| Compression | `CONFIGURE COMPRESSION ALGORITHM 'MEDIUM'` (basic, no ACO) | sql/10 | ✅ |
| Centralized catalog | `rman_cat` in PDB RCATPDB on rcat01 | sql/01,02,03 | ✅ Sprint 1 |

## ❌ What we do NOT simulate

- **Block-level deduplication** — exclusively a ZDLRA HW feature
- **Tape-out integration** — no tape library in the LAB
- **Cross-RA replication** — no second appliance
- **Hardware-accelerated compression** — basic compression is software-only
- **Real-time validation** — our validate is manual (`rman_validate.sh`)

## 🚀 Setup (one-off)

ZDLRA-like setup has 3 stages: (1) listener on rcat01 with static service `rcat_redo`, (2) TNS alias on PRIM, (3) real-time redo init + initial Level 0 IMAGE COPY on PRIM. Stages 1-2 are **inherently manual** (edit Oracle Net config files), stage 3 has Method A/B.

### 📋 Pre-checks

- ✅ PRIM registered in catalog (Sprint 1 step 3a — `SELECT name, dbid FROM rc_database;` returns PRIM)
- ✅ Persistent RMAN config done (Sprint 2 — `SHOW ALL` in RMAN shows 9 CONFIGURE settings)
- ✅ `/mnt/rman_bck` mounted on prim01 (`mount | grep rman_bck`)
- ✅ Network reachability: prim01 → rcat01:1521 (`ping rcat01.lab.local`)
- ✅ Logged in as `oracle` on prim01 (stages 1, 3) and `oracle` on rcat01 (stage 2 — listener)

### Stage 1 — Listener on rcat01 (static service `rcat_redo`)

Real-time redo requires **static service registration** in the rcat01 listener. Dynamic registration via DBMS only works when DB is OPEN — for redo apply we need the service even when DB is MOUNTED.

#### 🚀 Method A — automated (recommended)

One-liner: SSH to rcat01 → append to `listener.ora` (idempotent: checks if `rcat_redo` is already there) → reload + verify.

```bash
ssh oracle@rcat01 'bash -lc "
LF=\$ORACLE_HOME/network/admin/listener.ora
if grep -q \"GLOBAL_DBNAME=rcat_redo\" \$LF 2>/dev/null; then
  echo \"[skip] rcat_redo already in \$LF\"
else
  cat >> \$LF <<EOF

SID_LIST_LISTENER=
  (SID_LIST=
    (SID_DESC=
      (GLOBAL_DBNAME=rcat_redo)
      (ORACLE_HOME=\$ORACLE_HOME)
      (SID_NAME=RCAT)
    )
  )
EOF
  echo \"[added] rcat_redo to \$LF\"
fi
lsnrctl reload
lsnrctl status | grep -i rcat_redo
"'
# Expected at end: 'Service "rcat_redo" has 1 instance(s)'
```

> 💡 **Idempotency:** the snippet greps before appending — re-run does not duplicate the entry.

#### 🛠️ Method B — manual (interactive)

```bash
ssh oracle@rcat01
vi $ORACLE_HOME/network/admin/listener.ora
# Append at end of file:
```

```
SID_LIST_LISTENER=
  (SID_LIST=
    (SID_DESC=
      (GLOBAL_DBNAME=rcat_redo)
      (ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1)
      (SID_NAME=RCAT)
    )
  )
```

```bash
# Save (:wq), then:
lsnrctl reload
lsnrctl status | grep -i rcat_redo
# Expected: 'Service "rcat_redo" has 1 instance(s)'
```

### Stage 2 — TNS alias on PRIM

PRIM connects to `rcat_redo` via the TNS alias defined in `tnsnames.ora` on prim01 (and prim02 for RAC).

#### 🚀 Method A — automated (recommended)

One-liner: SSH to prim01 → append to `tnsnames.ora` (idempotent) → tnsping verify.

```bash
ssh oracle@prim01 'bash -lc "
TF=\$TNS_ADMIN/tnsnames.ora
if grep -q \"^RCAT01_REDO\" \$TF 2>/dev/null; then
  echo \"[skip] RCAT01_REDO already in \$TF\"
else
  cat >> \$TF <<EOF

RCAT01_REDO =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = rcat01.lab.local)(PORT = 1521))
    (CONNECT_DATA =
      (SERVICE_NAME = rcat_redo)
      (SERVER = DEDICATED)
    )
  )
EOF
  echo \"[added] RCAT01_REDO to \$TF\"
fi
tnsping RCAT01_REDO
"'
# Expected at end: 'OK (XX msec)'
```

> 💡 **For RAC (prim02):** repeat with `ssh oracle@prim02 ...` (tnsnames.ora is per-host, not shared).

> ⚠️ **Lesson #13:** `tnsping` requires PATH set by `~/.bash_profile` — `bash -lc` ensures a login shell.

#### 🛠️ Method B — manual (interactive)

```bash
ssh oracle@prim01
echo $TNS_ADMIN
# Verify location (typically /u01/app/oracle/product/23.26/dbhome_1/network/admin/)
vi $TNS_ADMIN/tnsnames.ora
# Append at end of file:
```

```
RCAT01_REDO =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = rcat01.lab.local)(PORT = 1521))
    (CONNECT_DATA =
      (SERVICE_NAME = rcat_redo)
      (SERVER = DEDICATED)
    )
  )
```

```bash
# Save (:wq), then verify:
tnsping RCAT01_REDO
# Expected: 'OK (XX msec)'
```

### Stage 3 — Real-time redo + initial Level 0 IMAGE COPY

This is the core of the ZDLRA-like configuration: setting `LOG_ARCHIVE_DEST_3` (ASYNC redo to rcat01) + a one-time `BACKUP INCREMENTAL LEVEL 0 AS COPY DATABASE` (image copy, NOT backupset). The script `zdlra_sim_setup.sh --init` does both in sequence.

#### 🚀 Method A — automated (recommended)

```bash
# Locally on prim01 as oracle:
ssh oracle@prim01
bash /tmp/scripts/zdlra_sim_setup.sh --init

# Or remotely from host (after ssh_setup.sh full mesh):
ssh oracle@prim01 'bash /tmp/scripts/zdlra_sim_setup.sh --init'
```

The script performs (v1.3+):
1. `ALTER SYSTEM SET LOG_ARCHIVE_CONFIG='DG_CONFIG=(PRIM,STBY,RCAT)'` — adds **RCAT** (target db_unique_name) to DG (lesson #26, otherwise ORA-16053)
2. `ALTER SYSTEM SET LOG_ARCHIVE_DEST_3='SERVICE=RCAT01_REDO ASYNC NOAFFIRM ... DB_UNIQUE_NAME=RCAT'` — DB_UNIQUE_NAME must be the actual `db_unique_name` of the target DB (NOT the service alias, lesson #28, otherwise ORA-16191)
3. `ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_3=ENABLE`
4. `ALTER SYSTEM SWITCH LOGFILE` (force real-time apply test)
5. `BACKUP INCREMENTAL LEVEL 0 AS COPY DATABASE FORMAT '/mnt/rman_bck/incr_merge/df_%d_%U'` (image copy, ~1 minute on a 50GB DB)
6. `LIST COPY OF DATABASE TAG 'incr_merge'` — validation

#### 🛠️ Method B — manual (interactive)

**Step 3.1 — Real-time redo (sqlplus as sysdba):**

```bash
ssh oracle@prim01
sqlplus / as sysdba
```

```sql
-- STEP 3.1a: Add RCAT (target db's db_unique_name) to DG_CONFIG.
-- Lesson #26: without this ALTER LOG_ARCHIVE_DEST_3 returns:
-- 'ORA-02097: parameter cannot be modified ... ORA-16053: DB_UNIQUE_NAME ...
--  is not in the Data Guard Configuration'
-- IMPORTANT Lesson #28: in DG_CONFIG and DB_UNIQUE_NAME (below) it MUST be the actual
-- target db_unique_name ('SELECT db_unique_name FROM v$database' on rcat01 = 'RCAT'),
-- NOT the TNS service alias ('rcat_redo'). Otherwise DEST_3 status=ERROR ORA-16191
-- 'log shipping client unable to log onto target database' (Oracle validates match).
ALTER SYSTEM SET LOG_ARCHIVE_CONFIG='DG_CONFIG=(PRIM,STBY,RCAT)' SCOPE=BOTH;

-- STEP 3.1b: Configure LOG_ARCHIVE_DEST_3 (real-time redo to RCAT database on rcat01).
-- SERVICE=RCAT01_REDO -> TNS alias on prim01 maps to rcat01:1521 SERVICE_NAME=rcat_redo
--                        (static service in listener.ora on rcat01)
-- DB_UNIQUE_NAME=RCAT -> actual db_unique_name of target DB (from v$database)
ALTER SYSTEM SET LOG_ARCHIVE_DEST_3=
  'SERVICE=RCAT01_REDO ASYNC NOAFFIRM
   VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE)
   DB_UNIQUE_NAME=RCAT' SCOPE=BOTH;

ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_3=ENABLE SCOPE=BOTH;

ALTER SYSTEM SWITCH LOGFILE;

-- Validation: dest_id=3 must be VALID, error=null
SELECT dest_id, dest_name, status, error FROM v$archive_dest WHERE dest_id IN (1,2,3);
EXIT
```

**Step 3.2 — Initial Level 0 IMAGE COPY (RMAN):**

```bash
rman target / catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB"
```

```rman
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
  ALLOCATE CHANNEL c2 DEVICE TYPE DISK;
  BACKUP
    INCREMENTAL LEVEL 0
    AS COPY
    TAG 'incr_merge'
    DATABASE
    FORMAT '/mnt/rman_bck/incr_merge/df_%d_%U';
  RELEASE CHANNEL c1;
  RELEASE CHANNEL c2;
}
LIST COPY OF DATABASE TAG 'incr_merge';
EXIT
```

> 💡 **Shortcut:** you can skip the entire `RUN { }` block — RMAN will use default channels from our `CONFIGURE DEVICE TYPE DISK PARALLELISM 4`:
> ```rman
> BACKUP INCREMENTAL LEVEL 0 AS COPY TAG 'incr_merge' DATABASE FORMAT '/mnt/rman_bck/incr_merge/df_%d_%U';
> ```

### ✅ Validation after setup

```bash
# Status (via wrapper)
ssh oracle@prim01 'bash /tmp/scripts/zdlra_sim_setup.sh --status'

# Or manually
sqlplus -S 'rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB' <<'SQL'
SET LINESIZE 150 PAGESIZE 50

-- Image copies in the catalog (file_type='X' = COPY in RMAN nomenclature)
SELECT s.db_unique_name, COUNT(*) AS files,
       ROUND(SUM(p.bytes)/1024/1024/1024, 2) AS total_gb
  FROM rc_backup_set s
  JOIN rc_backup_piece p ON s.bs_key = p.bs_key
 WHERE s.tag = 'INCR_MERGE'
 GROUP BY s.db_unique_name;

-- Or for image copies (RC_DATAFILE_COPY, not BACKUP_PIECE):
SELECT name, ROUND(blocks*block_size/1024/1024,1) AS mb
  FROM rc_datafile_copy
 WHERE tag = 'INCR_MERGE'
 ORDER BY name;

EXIT
SQL
```

> ⚠️ **Lesson #22:** in 26ai `RC_BACKUP_SET` has no byte columns — JOIN to `RC_BACKUP_PIECE`. Image copies are additionally visible in `RC_DATAFILE_COPY`.

## ⚠️ Lesson #29: Real-time redo to rcat01 — architectural limit

**Empirically verified 2026-05-04 iter.14 autonomous fix:** despite correct configuration (TNS, listener, DG_CONFIG, DB_UNIQUE_NAME, pwfile binary sync), real-time redo to rcat01 returns **`ORA-16009: invalid redo transport destination`**. Reason: Oracle DG redo transport requires a **physical standby** target — identical `db_name` + `dbid`. RCAT has `db_name=RCAT/dbid=1004435869`, PRIM has `db_name=PRIM/dbid=229119773`. Fundamental mismatch.

**Therefore in this LAB:**
- ✅ **Image copy + L1 incremental merge** (`--init` / `--merge`) → WORKS, the essence of ZDLRA-Like
- 🔒 **Real-time redo (`LOG_ARCHIVE_DEST_3`)** → DEFERRED, cannot be enabled without a full physical standby of PRIM on rcat01
- ✅ **Practical workaround for ~15 min RPO**: `rman_archivelog_only.sh` cron on PRIM (archive logs land in `/mnt/rman_bck/arch/` shared folder, accessible from rcat01)

**Full diagnostic + fix log:** [autonomous_dest3_log.md](../autonomous_dest3_log.md) (EN) / [autonomous_dest3_log_PL.md](../autonomous_dest3_log_PL.md) (PL).

**To clear ERROR from v$archive_dest** (after attempting DEST_3 setup):
```sql
ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_3=DEFER SCOPE=BOTH;
-- Status: DEFERRED (config preserved, no cycling errors)
```

### 🔮 Possible LAB extension: Sprint 5 (optional) — physical standby of PRIM on rcat01

To unlock real-time redo (`DEST_3`) + **Zero RPO recovery** scenario (potential B-9 in doc 08), you can build a **second Oracle instance** on rcat01 = physical standby of PRIM. It does NOT replace the existing `RCAT` (recovery catalog) — it runs **alongside**, on separate storage / separate SID.

#### 🛠️ High-level steps

| # | Step |
|---|---|
| 1 | **Storage:** second ASM diskgroup `+DATA_RCAT` (or `/u02/oradata/PRIM_RCAT/`) on rcat01, ~10 GB |
| 2 | **Listener:** static SID `PRIM_RCAT` in listener.ora on rcat01 + `lsnrctl reload` |
| 3 | **TNS on PRIM:** add `PRIM_RCAT = (HOST=rcat01)(SERVICE_NAME=PRIM_RCAT)` to tnsnames |
| 4 | **PFILE on rcat01:** `db_name=PRIM`, `db_unique_name=PRIM_RCAT`, `fal_server=PRIM`, `standby_file_management=AUTO` |
| 5 | **Pwfile sync (critical — Lesson #27):** binary-identical with PRIM via `DBMS_FILE_TRANSFER` from `+DATA/PRIM/PASSWORD/pwdprim.*` → scp → `$ORACLE_HOME/dbs/orapwPRIM_RCAT` |
| 6 | **Aux startup:** `STARTUP NOMOUNT PFILE='/tmp/init_prim_rcat.ora'` on rcat01 |
| 7 | **DUPLICATE FOR STANDBY** (from PRIM) — see block below |
| 8 | **Data Guard:** `dgmgrl` → `ADD DATABASE PRIM_RCAT AS CONNECT IDENTIFIER IS PRIM_RCAT MAINTAINED AS PHYSICAL` |
| 9 | **Activate DEST_3:** `ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_3=ENABLE` on PRIM (after DG ADD broker manages it automatically) |
| 10 | **Validate:** `v$archive_dest dest_id=3 STATUS=VALID`, `v$managed_standby` on PRIM_RCAT shows MRP0 APPLYING_LOG, `log_apply_lag=0` |

#### 📝 RMAN DUPLICATE FOR STANDBY (step 7)

```rman
# From prim01 as oracle:
rman target / auxiliary sys/${LAB_PASS}@rcat01:1521/PRIM_RCAT \
     catalog rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB

DUPLICATE TARGET DATABASE FOR STANDBY FROM ACTIVE DATABASE
  DORECOVER
  NOFILENAMECHECK
  SPFILE
    SET db_unique_name='PRIM_RCAT'
    SET fal_server='PRIM'
    SET log_archive_config='DG_CONFIG=(PRIM,STBY,PRIM_RCAT)'
    SET log_archive_dest_2='SERVICE=PRIM ASYNC NOAFFIRM VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE) DB_UNIQUE_NAME=PRIM'
    SET db_file_name_convert='+DATA/PRIM','+DATA_RCAT/PRIM_RCAT'
    SET log_file_name_convert='+DATA/PRIM','+DATA_RCAT/PRIM_RCAT';
```

#### 📊 Cost vs benefit

| Aspect | Value |
|---|---|
| Storage | ~10 GB (datafiles + redo + archlogs) |
| RAM | ~2 GB for the new instance |
| CPU | Minimal (apply only, no OLTP) |
| Configuration | ~2-3 h: storage + DUPLICATE (~45 min) + DG broker + pwfile sync |
| ✅ Benefit: real-time redo to rcat01 | DEST_3 VALID, redo applied real-time |
| ✅ Benefit: Zero RPO recovery (B-9) | Recovery to last committed transaction without waiting for archlog switch |
| ✅ Benefit: ZDLRA-Like full semantics | Real-time redo + image copy = full ZDLRA architecture |

#### 🤔 Why not in the current LAB

- **8 backup/restore scenarios** (doc 08) + **Virtual Full Backup** (doc 07) **already cover ~80% of real ZDLRA workflow** without Sprint 5
- Practical workaround for ~15 min RPO already exists (`rman_archivelog_only.sh` cron + shared folder)
- Sprint 5 is a good candidate for **future iteration** when a Zero RPO demo is needed
- In real ZDLRA, this function is provided by **dedicated hardware** (Recovery Appliance), not a second standby

#### 🚫 What is NOT a Sprint 5 goal

- ❌ **Switchover/failover** — PRIM_RCAT stays **permanently in STANDBY role** (recovery storage role only)
- ❌ **Own observer** for DG PRIM↔PRIM_RCAT — existing observer for PRIM↔STBY suffices
- ❌ **MaxProtection** — optional, we already have `MaxPerformance` for PRIM↔STBY

> 💡 **Decision status:** Sprint 5 is **documented but not planned**. Trigger for implementation = need for Zero RPO recovery demo or real-time redo from recovery catalog host.

## 🔁 Running merge cycles

After setup (initial Level 0 IMAGE COPY exists), daily run the **incremental merge cycle**: apply previous increment to image copy + take a new increment for the next day. In LAB (powered-off VMs) we use **manual on-demand**.

### 📋 LAB workflow — manual on-demand (default)

| Action | What it does | When to run | Command |
|---|---|---|---|
| **`zdlra_sim_setup.sh --init`** | One-off: `LOG_ARCHIVE_DEST_3` + initial L0 IMAGE COPY | Once, after Stages 1-2 | `ssh oracle@prim01 'bash /tmp/scripts/zdlra_sim_setup.sh --init'` |
| **`zdlra_sim_setup.sh --merge`** | Daily merge: RECOVER COPY (apply prev incr) + new INCR L1 FOR RECOVER OF COPY | Once per LAB-uptime day, or before Sprint 2 test | `ssh oracle@prim01 'bash /tmp/scripts/zdlra_sim_setup.sh --merge'` |
| **`zdlra_sim_setup.sh --status`** | Diagnostics: dest_id=3 status + LIST COPY + size on disk | After init/merge for confirmation | `ssh oracle@prim01 'bash /tmp/scripts/zdlra_sim_setup.sh --status'` |

> 💡 **Suggested sequence after powering on the LAB** (if you want a fresh image copy + one merge cycle):
> ```bash
> # Only once (after manual Stages 1-2):
> ssh oracle@prim01 'bash /tmp/scripts/zdlra_sim_setup.sh --init'   # Initial L0 (~5 min)
>
> # Daily merge — run manually when you want a fresh image copy:
> ssh oracle@prim01 'bash /tmp/scripts/zdlra_sim_setup.sh --merge'  # ~1-2 min
> ssh oracle@prim01 'bash /tmp/scripts/zdlra_sim_setup.sh --status' # Verify
> ```

### 🚀 Production reference — cron snippet (NOT deployed in this LAB)

> ⚠️ **Reference only — this cron is NOT deployed in our LAB.** VMs are powered off and daily merge in offline windows simply never runs. For LAB workflow use the "Manual on-demand" section above. The snippet below documents **what a production policy would look like**.

```cron
# /var/spool/cron/oracle (on prim01) — PRODUCTION ONLY
# Production only — NOT deployed in this LAB

# Daily merge — every day at 03:00 (after archivelog backup at 02:00)
0 3 * * * /home/oracle/scripts/zdlra_sim_setup.sh --merge
```

### 📝 Manual RMAN commands (copy/paste, no wrapper)

Raw RMAN commands for the incremental-merge pattern (Virtual Full Backup) — copy/paste into RMAN after `rman target / catalog ...`.

#### 🔵 Initial Level 0 IMAGE COPY (one-off, after Stage 2)

```rman
BACKUP INCREMENTAL LEVEL 0 AS COPY TAG 'incr_merge' DATABASE
  FORMAT '/mnt/rman_bck/incr_merge/df_%d_%U';
```

#### 🟡 Daily merge cycle (step 1 of 2 — apply previous incremental)

```rman
RECOVER COPY OF DATABASE WITH TAG 'incr_merge';
```

> 💡 **Day 1:** RECOVER COPY finds the image copy but **no increment** to apply → no-op (message "no incremental backup to apply"). From day 2 it actually applies the previous L1.

#### 🟢 Daily merge cycle (step 2 of 2 — new incremental for next merge)

```rman
BACKUP
  INCREMENTAL LEVEL 1
  FOR RECOVER OF COPY WITH TAG 'incr_merge'
  DATABASE
  FORMAT '/mnt/rman_bck/incr_merge/incr_%d_%U';
```

> 💡 **Key:** `FOR RECOVER OF COPY` changes the semantics — RMAN knows this increment will later be applied to the image copy (not restored separately).

#### 📋 Validate image copy + last incremental

```rman
LIST COPY OF DATABASE TAG 'incr_merge';
LIST BACKUP OF DATABASE TAG 'incr_merge';

# Disk usage:
HOST 'du -sh /mnt/rman_bck/incr_merge/';
```

#### 🚪 Exit

```rman
EXIT
```

## 🔄 How incremental-merge (Virtual Full Backup) works

```
Day 0 (init):
   image_copy_v0 = full database copy (Level 0)

Day 1:
   incr_l1_d1 = changes since day 0 (Level 1 cumulative)
   RECOVER COPY OF DATABASE -> applies incr_l1_d1 to image_copy
   image_copy_v0 turns into image_copy_v1 (like a fresh L0)

Day 2:
   incr_l1_d2 = changes since day 1
   RECOVER COPY -> image_copy_v2

... and so on.

Net effect: always one fresh image copy + small incremental, WITHOUT the cost of a full L0.
```

This is **the core ZDLRA function** in plain RMAN. It produces a "Virtual Full Backup" (RMAN terminology).

## ✅ Runtime validation

Post-setup validation (whether Stage 3 worked) is in "✅ Validation after setup" above. This section — **runtime health check**: whether real-time redo is still flowing, archive logs arriving at rcat01, image copy + last incremental are consistent.

### Quick check via wrapper

```bash
ssh oracle@prim01 'bash /tmp/scripts/zdlra_sim_setup.sh --status'

# Expected:
# 1) LOG_ARCHIVE_DEST_3 status: VALID, error=(null)
# 2) LIST COPY OF DATABASE TAG 'incr_merge' shows the image copy
# 3) du /mnt/rman_bck/incr_merge/ ~50 GB (image copy) + ~1-3 GB (last incremental)
```

### Sql queries (on PRIM as sysdba)

```sql
-- 1) Real-time redo destination alive
SELECT dest_id, dest_name, status, error
  FROM v$archive_dest WHERE dest_id=3;
-- Expected: status=VALID, error=(null)

-- 2) Latest archive logs sent to rcat01 (dest_id=3)
SELECT name, sequence#, status FROM v$archived_log
  WHERE dest_id=3 ORDER BY sequence# DESC FETCH FIRST 5 ROWS ONLY;
-- Should show ascending sequence numbers, status='A' (Available)

-- 3) Verify the latest log switch reached dest_id=3 (lag check)
SELECT thread#, MAX(sequence#) AS max_seq,
       MAX(CASE WHEN dest_id=1 THEN sequence# END) AS local_seq,
       MAX(CASE WHEN dest_id=3 THEN sequence# END) AS rcat_seq
  FROM v$archived_log
 WHERE first_time > SYSDATE - 1/24
 GROUP BY thread#;
-- local_seq = rcat_seq -> redo apply real-time
-- local_seq > rcat_seq -> there's a lag (ASYNC normal if <5)
```

### Sql queries (on rcat01 as rman_cat)

```sql
-- 4) Image copy + incremental in catalog (size)
SELECT name, ROUND(blocks*block_size/1024/1024, 1) AS size_mb,
       TO_CHAR(creation_time, 'YYYY-MM-DD HH24:MI') AS created
  FROM rc_datafile_copy
 WHERE tag = 'INCR_MERGE'
 ORDER BY name;

-- 5) Last incremental L1 (for the next merge)
SELECT s.bs_key, s.tag, s.incremental_level, s.pieces,
       TO_CHAR(s.completion_time, 'YYYY-MM-DD HH24:MI') AS done,
       ROUND(SUM(p.bytes)/1024/1024, 1) AS size_mb
  FROM rc_backup_set s
  JOIN rc_backup_piece p ON s.bs_key = p.bs_key
 WHERE s.tag = 'INCR_MERGE' AND s.incremental_level = 1
 GROUP BY s.bs_key, s.tag, s.incremental_level, s.pieces, s.completion_time
 ORDER BY s.completion_time DESC FETCH FIRST 3 ROWS ONLY;
```

> ⚠️ **Lesson #22:** in 26ai bytes are in `RC_BACKUP_PIECE` (per-piece, JOIN by `bs_key`), NOT in `RC_BACKUP_SET`. Image copies are in `RC_DATAFILE_COPY` (a separate view from backupsets).

## 🚧 Troubleshooting

| Problem | Resolution |
|---|---|
| `error 12541 TNS:no listener` | `lsnrctl status` on rcat01, check that `rcat_redo` is registered (Stage 1) |
| `error 1031 insufficient privileges` | LOG_ARCHIVE_DEST requires REDO_TRANSPORT_USER or SYS-as-sysdba with a static service |
| Image copy grows disproportionately | After `RECOVER COPY` the previous version should be removed — check `LIST COPY` |
| Incremental merge takes a long time | `PARALLELISM` in 10_rman_config_persistent.sql or in `RUN { ALLOCATE CHANNEL ... }` |
| `RMAN-02001 unrecognized punctuation symbol "-"` | RMAN doesn't accept `--` as comment, use `#` (lesson #20). Check `*.sql` files and bash heredocs |
| `PLS-00201: identifier 'DBMS_LOCK' must be declared` | Lesson #21: `GRANT EXECUTE ON SYS.DBMS_LOCK TO rman_cat;` in PDB RCATPDB |
| Script `--init` or `--merge` shows nothing, log file empty | Lesson #24: `set -u` + `source ~/.bash_profile` silent crash. Wrap source in `set +u; source ...; set -u` |
| ARC0 process busy/slow | Check net latency `tnsping rcat01_redo`, redo network bottleneck — in LAB usually <50ms |

## 📊 Comparison: Standard backup vs Virtual Full

| Metric | Standard (FULL weekly) | Virtual Full (incremental merge) |
|---|---|---|
| Full backup time | ~1h (for 50 GB DB) | ~5 min (initial), 1 min (daily merge) |
| Storage I/O | high once a week | evenly distributed, small |
| Recovery time from latest | ~30 min (FULL + arch) | ~10 min (image copy + arch) |
| Retention granularity | week | day |
| Required licensing | none | none (plain RMAN) |

## ⏭️ Next step

[09_DG_Integration.md](09_DG_Integration.md) — Backup ↔ Data Guard integration (rebuild standby from backup).
