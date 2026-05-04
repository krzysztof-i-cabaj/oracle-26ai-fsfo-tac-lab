# 🗓️ 06 — Backup Policy (Sprint 2)

[![Sprint](https://img.shields.io/badge/Sprint-2-blue)]()
[![Component](https://img.shields.io/badge/Component-RMAN_Policy-red)]()
[![Cycles](https://img.shields.io/badge/Cycles-Weekly%20%2B%20Daily%20%2B%2015min-success)]()
[![Retention](https://img.shields.io/badge/Retention-14_days-orange)]()
[![Compression](https://img.shields.io/badge/Compression-Basic_%22MEDIUM%22-darkgreen)]()

> 🎯 Backup cycle policy for the PRIM database: weekly Level 0 + daily incremental L1 + archivelog every 15 min.

## 📊 Backup cycles

| Type | Frequency | Script | Retention | Location |
|---|---|---|---|---|
| **Full L0** | weekly (Sun 02:00) | `rman_full_backup.sh` | 4 weeks | `/mnt/rman_bck/full/` |
| **Incremental L1 cumulative** | daily (02:00) | `rman_incremental_l1.sh` | 7 days | `/mnt/rman_bck/incr/` |
| **Archivelog** | every 15 min | `rman_archivelog_only.sh` | until BACKED_UP 2 times | `/mnt/rman_bck/arch/` |
| **Controlfile autobackup** | after every structure change | (automatic) | overlay with FULL | `/mnt/rman_bck/cf/` |
| **Crosscheck + cleanup** | weekly | `rman_crosscheck.sh` | — | — |
| **Validate** | weekly (after FULL) | `rman_validate.sh` | — | — |

## ⚙️ Persistent RMAN config (one-off setup)

Backup policy = persistent RMAN settings stored in the catalog (`rcat01`). Run **once** after registering PRIM (Sprint 1 step 3a). Source: [`sql/10_rman_config_persistent.sql`](../sql/10_rman_config_persistent.sql).

### 📋 Pre-checks

- ✅ PRIM registered in catalog (`SELECT name, dbid FROM rc_database;` returns PRIM)
- ✅ `/mnt/rman_bck` mounted on prim01 (`mount | grep rman_bck`)
- ✅ Logged in as `oracle` on prim01 (`whoami` = oracle)

### 🚀 Method A — automated (recommended)

**Variant 1 — locally on prim01:**

```bash
ssh oracle@prim01
bash /tmp/scripts/rman_setup_config.sh
```

**Variant 2 — remotely from rcat01 (after `ssh_setup.sh` full mesh):**

```bash
ssh oracle@rcat01 'ssh oracle@prim01 "bash /tmp/scripts/rman_setup_config.sh"'
```

The script:
1. Sources LAB_PASS, verifies pre-checks (oracle user, sql file, /mnt/rman_bck).
2. Creates subdirectories `/mnt/rman_bck/{cf,full,incr,arch}` if missing.
3. `rman target / catalog ... @sql/10_rman_config_persistent.sql` — applies 9 CONFIGURE settings.
4. Validation: `SHOW RETENTION POLICY; SHOW BACKUP OPTIMIZATION; ... SHOW SNAPSHOT CONTROLFILE NAME;` — confirms the 9 entries.

**Idempotency:** RMAN CONFIGURE overwrites values without error, so re-run is safe.

### 🛠️ Method B — manual (interactive)

```bash
# Step 1: SSH to prim01 as oracle
ssh oracle@prim01

# Step 2: Connect to RMAN with TARGET=PRIM (local OS auth) and CATALOG=rcat01
# IMPORTANT: $LAB_PASS contains '!' — use single quotes or ${LAB_PASS} in double quotes.
rman target / catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB"
```

**Variant 2a — via SQL file (recommended manual):**

```rman
RMAN> @/tmp/sql/10_rman_config_persistent.sql
# Applies 9 CONFIGURE + SHOW ALL at the end

RMAN> EXIT;
```

**Variant 2b — line by line:**

```rman
RMAN> CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 14 DAYS;
RMAN> CONFIGURE BACKUP OPTIMIZATION ON;
RMAN> CONFIGURE CONTROLFILE AUTOBACKUP ON;
RMAN> CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '/mnt/rman_bck/cf/cf_%F';
RMAN> CONFIGURE DEVICE TYPE DISK PARALLELISM 4 BACKUP TYPE TO BACKUPSET;
RMAN> CONFIGURE COMPRESSION ALGORITHM 'MEDIUM';
RMAN> CONFIGURE CHANNEL DEVICE TYPE DISK FORMAT '/mnt/rman_bck/full/bp_%U';
RMAN> CONFIGURE ARCHIVELOG DELETION POLICY TO BACKED UP 2 TIMES TO DISK;
RMAN> CONFIGURE SNAPSHOT CONTROLFILE NAME TO '/u01/app/oracle/snapcf_PRIM.f';

RMAN> SHOW ALL;
RMAN> EXIT;
```

> 💡 **`COMPRESSION ALGORITHM 'MEDIUM'`** = basic compression. No ACO licence required. `LOW`/`HIGH` require ACO — **we do not assume it**.

### ✅ Validation after setup

```bash
# From any client with access to rcat01 (host, rcat01, prim01)
rman target / catalog rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB
RMAN> SHOW ALL;
```

Expected (9 persistent settings stored in the catalog):

| # | CONFIGURE | Expected value |
|---|---|---|
| 1 | RETENTION POLICY | `RECOVERY WINDOW OF 14 DAYS` |
| 2 | BACKUP OPTIMIZATION | `ON` |
| 3 | CONTROLFILE AUTOBACKUP | `ON` |
| 4 | CONTROLFILE AUTOBACKUP FORMAT | `/mnt/rman_bck/cf/cf_%F` |
| 5 | DEVICE TYPE DISK | `PARALLELISM 4 BACKUP TYPE TO BACKUPSET` |
| 6 | COMPRESSION ALGORITHM | `MEDIUM` |
| 7 | CHANNEL DEVICE TYPE DISK FORMAT | `/mnt/rman_bck/full/bp_%U` |
| 8 | ARCHIVELOG DELETION POLICY | `BACKED UP 2 TIMES TO DISK` |
| 9 | SNAPSHOT CONTROLFILE NAME | `/u01/app/oracle/snapcf_PRIM.f` |

## 🔁 Running backup cycles

All backup scripts are run **from prim01 as oracle** (TARGET=local). In this LAB part the VMs are **often powered off** — cron jobs barely ever fire on scheduled windows (classic cron does not catch up on missed runs). Default workflow: **manual on-demand**.

### 📋 LAB workflow — manual on-demand (default)

After powering up the LAB and before working on backups, run these scripts **selectively** depending on the scenario:

| Script | What it does | When to run | Command (from host or after `ssh prim01`) |
|---|---|---|---|
| **`rman_full_backup.sh`** | FULL L0 (Level 0) + ARCHIVELOG + autobackup CF | First backup after policy setup, "fresh database" for Sprint 2 | `ssh oracle@prim01 'bash /tmp/scripts/rman_full_backup.sh'` |
| **`rman_incremental_l1.sh`** | Incremental L1 CUMULATIVE + ARCHIVELOG | After FULL — verifies that incremental works on top of Level 0 | `ssh oracle@prim01 'bash /tmp/scripts/rman_incremental_l1.sh'` |
| **`rman_archivelog_only.sh`** | Backup of archivelogs only (light, fast) | Frequent log switches / before DG switchover / before LAB shutdown | `ssh oracle@prim01 'bash /tmp/scripts/rman_archivelog_only.sh'` |
| **`rman_crosscheck.sh`** | CROSSCHECK + DELETE EXPIRED + DELETE OBSOLETE | After artificially deleting backup files from disk / catalog cleanup | `ssh oracle@prim01 'bash /tmp/scripts/rman_crosscheck.sh'` |
| **`rman_validate.sh`** | RESTORE DATABASE VALIDATE — verifies backup integrity without restoring | After FULL+INCR — confidence that backups are usable | `ssh oracle@prim01 'bash /tmp/scripts/rman_validate.sh'` |

> 💡 **Suggested "from-scratch" sequence after powering on the LAB** (when you want fresh data for scenarios B-1..B-6):
> ```bash
> ssh oracle@prim01 'bash /tmp/scripts/rman_full_backup.sh'        # 1. FULL L0 (~2-5 min)
> ssh oracle@prim01 'bash /tmp/scripts/rman_incremental_l1.sh'     # 2. INCR L1 (~30 sec)
> ssh oracle@prim01 'bash /tmp/scripts/rman_archivelog_only.sh'    # 3. ARCH (~10 sec)
> ssh oracle@prim01 'bash /tmp/scripts/rman_validate.sh'           # 4. VALIDATE (~1-2 min)
> ```

### 📝 Manual RMAN commands (copy/paste, no wrapper)

Sometimes it's easier to paste raw RMAN commands than to run a script — e.g. ad-hoc backup, debugging, education, or when a script fails and you need to understand why. Ready-to-paste blocks below.

```bash
# Step 1: SSH + RMAN connect (common for all operations below)
ssh oracle@prim01
rman target / catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB"
```

#### 🔵 FULL backup (Level 0)

```rman
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK FORMAT '/mnt/rman_bck/full/db_%d_%T_%U';
  ALLOCATE CHANNEL c2 DEVICE TYPE DISK FORMAT '/mnt/rman_bck/full/db_%d_%T_%U';
  ALLOCATE CHANNEL c3 DEVICE TYPE DISK FORMAT '/mnt/rman_bck/full/db_%d_%T_%U';
  ALLOCATE CHANNEL c4 DEVICE TYPE DISK FORMAT '/mnt/rman_bck/full/db_%d_%T_%U';
  BACKUP
    INCREMENTAL LEVEL 0
    AS COMPRESSED BACKUPSET
    TAG 'manual_full'
    DATABASE
    PLUS ARCHIVELOG
      FORMAT '/mnt/rman_bck/arch/arc_%d_%T_%U'
      DELETE INPUT;
  RELEASE CHANNEL c1; RELEASE CHANNEL c2; RELEASE CHANNEL c3; RELEASE CHANNEL c4;
}
```

> 💡 **Shortcut thanks to CONFIGURE:** you can skip the whole `RUN { }` block and RMAN will use default channels from `CONFIGURE DEVICE TYPE DISK PARALLELISM 4`:
> ```rman
> BACKUP INCREMENTAL LEVEL 0 AS COMPRESSED BACKUPSET TAG 'manual_full' DATABASE PLUS ARCHIVELOG;
> ```

#### 🟡 Incremental Level 1 (CUMULATIVE)

```rman
BACKUP
  INCREMENTAL LEVEL 1 CUMULATIVE
  AS COMPRESSED BACKUPSET
  TAG 'manual_incr'
  FORMAT '/mnt/rman_bck/incr/incr_%d_%T_%U'
  DATABASE
  PLUS ARCHIVELOG;
```

#### 🟢 Archivelog only (light, fast)

```rman
BACKUP
  AS COMPRESSED BACKUPSET
  TAG 'manual_arch'
  FORMAT '/mnt/rman_bck/arch/arc_%d_%T_%U'
  ARCHIVELOG ALL
  NOT BACKED UP 1 TIMES
  DELETE ALL INPUT;
```

#### 🔍 Crosscheck + cleanup (sync catalog with disk)

```rman
CROSSCHECK BACKUP;
CROSSCHECK ARCHIVELOG ALL;

DELETE NOPROMPT EXPIRED BACKUP;
DELETE NOPROMPT EXPIRED ARCHIVELOG ALL;
DELETE NOPROMPT OBSOLETE;
```

#### ✅ Validate (verify integrity without restoring)

```rman
RESTORE DATABASE VALIDATE;
RESTORE ARCHIVELOG ALL VALIDATE;

# Validate a specific backup set (if you know BS_KEY from RC_BACKUP_SET):
# VALIDATE BACKUPSET <bs_key>;
```

#### 📋 LIST / REPORT (diagnostics, no modification)

```rman
LIST BACKUP SUMMARY;
LIST BACKUP SUMMARY COMPLETED AFTER 'SYSDATE-1';
LIST DB_UNIQUE_NAME ALL;

REPORT SCHEMA;
REPORT NEED BACKUP;
REPORT OBSOLETE;
REPORT UNRECOVERABLE;
```

#### 🚪 Exit

```rman
EXIT
```

---

### ✅ Validation after a manual run

> ⚠️ **Lesson learned 2026-05-04 iter.12:** in 26ai `RC_BACKUP_SET` does **NOT have** `INPUT_BYTES`, `OUTPUT_BYTES` or `COMPRESSION_RATIO` columns. Bytes are aggregated per-piece in `RC_BACKUP_PIECE.BYTES` — JOIN required. Also: `BACKUP DATABASE` returns `BACKUP_TYPE='I' INCREMENTAL_LEVEL=0` (NOT `'D'`!) — what users call "FULL" is formally *Incremental Level 0* in 26ai. Codes: **D**=Controlfile autobackup, **I**=Incremental (lvl 0 = full), **L**=Archivelog.

```bash
# What's registered in the catalog after the backup
sqlplus -S 'rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB' <<'SQL'
SET LINESIZE 160 PAGESIZE 50
COLUMN start_time FORMAT A19
COLUMN backup_type FORMAT A12
COLUMN status FORMAT A6

-- List of backup sets from the last hour
SELECT TO_CHAR(start_time,'YYYY-MM-DD HH24:MI:SS') AS start_time,
       backup_type, incremental_level AS lvl, status, pieces, elapsed_seconds AS elapsed_s
  FROM rc_backup_set
 WHERE start_time > SYSDATE - 1/24
 ORDER BY start_time;

-- Bytes per backup_type (JOIN to RC_BACKUP_PIECE)
SELECT s.backup_type, COUNT(*) AS pieces,
       ROUND(SUM(p.bytes)/1024/1024,1) AS total_mb
  FROM rc_backup_set s
  JOIN rc_backup_piece p ON s.bs_key = p.bs_key
 WHERE s.start_time > SYSDATE - 1/24
 GROUP BY s.backup_type
 ORDER BY 1;

EXIT
SQL

# Files on disk (actual backup pieces)
ssh oracle@prim01 'du -sh /mnt/rman_bck/{full,incr,arch,cf}/ 2>/dev/null'
```

**Expected after the first FULL:**
- `D` (controlfile) ~10-20 MB → `/mnt/rman_bck/cf/`
- `I lvl 0` (database) — several hundred MB → `/mnt/rman_bck/full/`
- `L` (archivelog) ~100-500 MB → `/mnt/rman_bck/arch/`

### 🚀 Production reference — cron snippet (NOT deployed in this LAB)

> ⚠️ **Reference only — this cron is NOT deployed in our LAB.** VMs are powered off and cron jobs in offline windows simply never run (classic cron does not catch up on missed runs). For LAB workflow use the "Manual on-demand" section above. The snippet below documents **what a production policy would look like** for comparison.

```cron
# /var/spool/cron/oracle (on prim01) — PRODUCTION ONLY
# Production only — NOT deployed in this LAB

# Archivelog every 15 min (RPO < 15 min)
*/15 * * * * /home/oracle/scripts/rman_archivelog_only.sh

# Daily incremental L1 — every day at 02:00 (except Sundays)
0 2 * * 1-6  /home/oracle/scripts/rman_incremental_l1.sh

# Weekly full L0 — Sunday at 02:00
0 2 * * 0    /home/oracle/scripts/rman_full_backup.sh

# Weekly crosscheck — Sunday at 04:00 (after FULL)
0 4 * * 0    /home/oracle/scripts/rman_crosscheck.sh

# Weekly validate — Sunday at 05:00
0 5 * * 0    /home/oracle/scripts/rman_validate.sh
```

**Production alternatives** (for machines that get powered off, e.g. dev environments):
- **`anacron`** — catches up missed jobs after boot (but in LAB it would fire FULL right after every power-on)
- **systemd timer + `Persistent=true`** — anacron equivalent with journal/observability
- **Cron on rcat01 + SSH to prim01** (orchestrator outside the target) — separation-of-duties

The choice requires a **policy** decision (backup windows, capacity planning, monitoring) — out of scope for this LAB.

## 📈 RPO / RTO

| Goal | Value | Mechanism |
|---|---|---|
| **RPO** (Recovery Point Objective) | **≤ 15 min** | Archivelog every 15 min |
| **RPO** (with real-time redo, Sprint 3) | **~0 s** (commit-level) | LOG_ARCHIVE_DEST_3 ASYNC to rcat01 |
| **RTO Full Recovery** | **~30-60 min** | Restore L0 + L1 + arch |
| **RTO PITR (single PDB)** | **~10-20 min** | Restore PDB datafiles only |
| **RTO Tablespace** | **~5-10 min** | Online tablespace recovery |
| **RTO Controlfile loss** | **~15 min** | Restore from autobackup |

## 🔢 Sizing /mnt/rman_bck

For PRIM ~ 50 GB datafiles + 1 GB redo/h, retention 14 days:

| Type | Frequency | Size (compressed) | Retention | Total |
|---|---|---|---|---|
| Full L0 | 1/week | ~25 GB | 4 weeks | **100 GB** |
| Incremental L1 | 6/week (Mon-Sat) | ~3 GB | 1 week | **18 GB** |
| Archivelog | 96/day (15 min) | ~250 MB/day | 14 days | **3.5 GB** |
| Controlfile | autobkup | ~10 MB × 50 | overlay | **0.5 GB** |
| **Total** | | | | **~125 GB** |

The shared folder `D:\_RMAN_BCK_from_Linux_` should have **at least 200 GB** (with margin).

## 🎯 Policy validation

```bash
# 1) After setup
rman target / catalog rman_cat/...@rcat01:1521/RCATPDB
RMAN> SHOW ALL;
# Should show all CONFIGURE settings

# 2) Ad-hoc backup test
bash rman_full_backup.sh
# Check execution time, size of /mnt/rman_bck/full/

# 3) Validate test
bash rman_validate.sh
# Should be clean, no 'failed' / 'corrupt'

# 4) After the first cycle iteration
sqlplus rman_cat/...@rcat01:1521/RCATPDB @sql/20_health_checks.sql
# Health checks 1-6 give a status overview
```

## 🚧 Troubleshooting

| Problem | Symptom | Resolution |
|---|---|---|
| `ORA-19809 limit exceeded for recovery files` | FRA full on PRIM | `rman_archivelog_only.sh` with DELETE ALL INPUT, or increase `db_recovery_file_dest_size` |
| Backup takes >> expected time | I/O bottleneck on vboxsf | Reduce PARALLELISM to 2, check host disk I/O |
| `RMAN-03002` in cron job | Cron env has no ORACLE_HOME | Scripts include `source ~/.bash_profile` |
| Crosscheck shows EXPIRED | Files removed manually from disk | `DELETE EXPIRED` in `rman_crosscheck.sh` cleans this up |
| Daily L1 has no base | No Level 0 yet | Run FULL first, then L1 (the script assumes this) |

## ⏭️ Next step

[07_ZDLRA_Like_Simulation.md](07_ZDLRA_Like_Simulation.md) — Sprint 3: real-time redo + virtual full backup.
