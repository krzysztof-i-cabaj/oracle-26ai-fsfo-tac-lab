# 📚 05 — Catalog Setup (Sprint 1, step 3)

[![Sprint](https://img.shields.io/badge/Sprint-1-blue)]()
[![Step](https://img.shields.io/badge/Step-3_of_4-orange)]()
[![Component](https://img.shields.io/badge/Component-RMAN_Catalog-red)]()
[![Schema](https://img.shields.io/badge/Schema-rman__cat-purple)]()
[![Container](https://img.shields.io/badge/PDB-RCATPDB-darkgreen)]()

> 🎯 Creates the `rman_cat` schema in PDB RCATPDB, runs `CREATE CATALOG`, registers the PRIM database.

## 🧠 What is the RMAN Recovery Catalog?

The Recovery Catalog is an RMAN metadata database that stores backup information for **multiple** target (TARGET) databases.
Without a catalog, RMAN keeps metadata only in the controlfile — which limits retention and history. With a catalog we can:
- Keep backup history > 7 days (controlfile cap)
- Centrally manage backups from many databases
- Use stored scripts (CREATE SCRIPT)
- Produce cross-database reports

Benefits summary: long retention history, centralized management, stored scripts, cross-DB reports.

## 📋 Prerequisites

- ✅ rcat01 has a working DB RCAT + PDB RCATPDB OPEN (Sprint 1 step 2)
- ✅ Listener on rcat01:1521 has registered the RCATPDB service
- ✅ rcat01:1521 is reachable over the network from prim01

## 🚀 Method A — Automated

```bash
# On rcat01 as oracle
ssh oracle@rcat01
bash /tmp/scripts/catalog_create.sh

# From the host (or rcat01) — register PRIM
ssh oracle@rcat01 'bash /tmp/scripts/catalog_register_prim.sh'

# From the host (or rcat01) — register STBY (CONFIGURE DB_UNIQUE_NAME + RESYNC)
# Pre-checks: DG broker SUCCESS, roles prim01=PRIMARY/stby01=PHYSICAL STANDBY,
# TNS aliases 'STBY' on prim01 and 'PRIM' on stby01, SSH equiv rcat01->prim01/stby01.
ssh oracle@rcat01 'bash /tmp/scripts/catalog_register_stby.sh'
```

## 🛠️ Method B — Manual (step by step)

### B.1) rman_cat schema (on rcat01)

```bash
# Connect to PDB RCATPDB as sys.
# IMPORTANT: $LAB_PASS contains '!' — bash interprets it as history expansion.
# Use single quotes around the connect string OR ${LAB_PASS} with double quotes.
sqlplus "sys/${LAB_PASS}@rcat01:1521/RCATPDB" AS SYSDBA
```

```sql
-- DBCA for 23ai/26ai does NOT set db_create_file_dest in the PDB — we must do it explicitly
-- (lesson learned 2026-05-03 iter.9: without it CREATE TABLESPACE without DATAFILE clause
-- returns ORA-02236 'invalid file name', and a hardcoded path '/u02/oradata/RCAT/rcatpdb/'
-- returns ORA-01119 because the PDB lives at '/u02/oradata/RCAT/RCATPDB/' (uppercase)).
ALTER SYSTEM SET db_create_file_dest = '/u02/oradata' SCOPE=BOTH;

-- Tablespace dedicated to the catalog (Oracle Managed Files — no DATAFILE clause).
-- Oracle places the file at /u02/oradata/RCAT/RCATPDB/datafile/o1_mf_<TS>_<HASH>_.dbf
CREATE TABLESPACE rcat_data
  DATAFILE SIZE 500M
  AUTOEXTEND ON NEXT 100M MAXSIZE 10G
  EXTENT MANAGEMENT LOCAL AUTOALLOCATE
  SEGMENT SPACE MANAGEMENT AUTO;

-- Catalog owner user (password from $LAB_PASS in /root/.lab_secrets)
CREATE USER rman_cat IDENTIFIED BY "<LAB_PASS_HERE>"
  DEFAULT TABLESPACE rcat_data
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON rcat_data;

-- Grants
GRANT CONNECT, RESOURCE TO rman_cat;
GRANT RECOVERY_CATALOG_OWNER TO rman_cat;

-- NOTE: lesson learned 2026-05-04 iter.12 — in 26ai the RECOVERY_CATALOG_OWNER role
-- does NOT auto-grant EXECUTE on DBMS_LOCK. Without it RMAN fails on connect with
-- PLS-00201 'identifier DBMS_LOCK must be declared' (it tries to acquire an upgrade lock).
-- Effect: BACKUP DATABASE PLUS ARCHIVELOG only backs up archivelogs, DATABASE itself NOT.
GRANT EXECUTE ON SYS.DBMS_LOCK TO rman_cat;

EXIT
```

### B.2) CREATE CATALOG (via RMAN)

```bash
# IMPORTANT: single quotes or ${LAB_PASS} (bash '!' history expansion).
rman catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB"
```

```rman
RMAN> CREATE CATALOG;
Recovery catalog created.

RMAN> EXIT;
```

Under the hood, RMAN creates in 26ai/23ai:
- **~62 base tables** (catalog metadata: BACKUP_PIECE_DETAILS, DBINC, BACKUP_CORRUPTION...)
- **~124 RCI_* views** (RMAN Catalog Internal — higher layer over the tables)
- **3 packages** (DBMS_RCVCAT, DBMS_RCVMAN_BACKUP, DBMS_RCVCAT_PRIV) + bodies + ~666 procedures/functions
- ~222 indexes, sequences, types

NOTE: Lesson learned 2026-05-03 iter.9 — `CREATE CATALOG` does NOT have a native `IF NOT EXISTS`.
Re-running returns `RMAN-06441 already exists`. If you must rebuild: `DROP CATALOG;` first.

NOTE: SQL scripts for RMAN use **`#` as a comment** (NOT `--` like SQL!). PL/SQL does not work
in an RMAN session — only RMAN commands + `SQL "..."` (caveat: `SQL` requires a TARGET database connection,
not a catalog connection). Validation of the rman_cat schema must be done SEPARATELY via sqlplus.

### B.3) REGISTER PRIM (on prim01)

```bash
ssh oracle@prim01
rman target / catalog rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB
```

```rman
RMAN> REGISTER DATABASE;
database registered in recovery catalog
starting full resync of recovery catalog
full resync complete

RMAN> RESYNC CATALOG;

RMAN> LIST DB_UNIQUE_NAME ALL;
RMAN> REPORT SCHEMA;
```

### B.4) REGISTER STBY (Data Guard standby)

A physical standby has **the SAME DBID** as the primary (DBID=229119773 in our case), so we do NOT use `REGISTER DATABASE` on stby01 — it would return `RMAN-20002 target database already registered`. Instead:
1. **From PRIMARY** we run `CONFIGURE DB_UNIQUE_NAME 'STBY' CONNECT IDENTIFIER 'STBY'` — this adds STBY as a *site* in the catalog (`RC_SITE`).
2. **From STANDBY** we run `RESYNC CATALOG FROM DB_UNIQUE_NAME 'STBY'` — pulls metadata from the standby controlfile (LIST BACKUP/COPY then sees backups taken on stby).

Summary: a physical standby shares the same DBID as the primary, so we don't `REGISTER DATABASE` on stby. Instead: `CONFIGURE DB_UNIQUE_NAME` from primary, then `RESYNC CATALOG FROM DB_UNIQUE_NAME 'STBY'` from standby.

**Pattern:**
```
PRIM (TARGET=PRIMARY) ──CONFIGURE DB_UNIQUE_NAME 'STBY' CONNECT IDENTIFIER 'STBY'──→ rcat01    # RC_SITE += STBY
STBY (TARGET=STANDBY) ──RESYNC CATALOG FROM DB_UNIQUE_NAME 'STBY'──→ rcat01                      # metadata from standby controlfile
```

> ⚠️ **DG role caveat:**
> `CONFIGURE DB_UNIQUE_NAME` is run with **TARGET = the database in the PRIMARY role** (regardless of naming convention). After an FSFO failover the roles may be reversed — in that case:
> - if prim01 (db_unique_name=PRIM) has the STANDBY role and stby01 (db_unique_name=STBY) has the PRIMARY role → first switchover back to the natural state (DGMGRL `SWITCHOVER TO PRIM`)
> - alternatively, run the commands the other way around (TARGET=stby01, add 'PRIM' as the standby) — but this is counterintuitive

#### B.4.1 — Pre-checks

```bash
# 1) DG broker SUCCESS, roles consistent with names
ssh infra01 "TNS_ADMIN=/etc/oracle/tns/obs_ext dgmgrl /@PRIM_ADMIN 'SHOW CONFIGURATION'"
# Expected: Configuration Status SUCCESS, prim01=primary, stby01=physical standby

# 2) TNS aliases 'PRIM' and 'STBY' in tnsnames.ora on prim01 (and both)
ssh oracle@prim01 'tnsping STBY'
# Expected: OK (XX msec)

# 3) APPLY-ON on stby01 (after a fresh shutdown the session may be APPLY-OFF)
ssh infra01 "TNS_ADMIN=/etc/oracle/tns/obs_ext dgmgrl /@PRIM_ADMIN 'EDIT DATABASE STBY SET STATE=APPLY-ON'"
```

#### B.4.2 — CONFIGURE DB_UNIQUE_NAME (from primary)

**Variant 2a — via SQL file (recommended):**

```bash
# Copy the file to prim01 (or run from a host with SSH equiv)
scp sql/04_register_stby.sql oracle@prim01:/tmp/

# Connect and run
ssh oracle@prim01
rman target / catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB" @/tmp/04_register_stby.sql
```

**Variant 2b — interactively (typing commands):**

```bash
ssh oracle@prim01
rman target / catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB"
```

```rman
# Add STBY as a site in the catalog
RMAN> CONFIGURE DB_UNIQUE_NAME 'STBY' CONNECT IDENTIFIER 'STBY';

# Validation — should show 2 sites: PRIM + STBY
RMAN> LIST DB_UNIQUE_NAME ALL;

RMAN> EXIT;
```

#### B.4.3 — RESYNC CATALOG FROM standby (on stby01)

**Variant 3a — via SQL file (recommended):**

```bash
# Copy the file to stby01 (or run from a host with SSH equiv)
scp sql/05_resync_stby.sql oracle@stby01:/tmp/

# Connect and run
ssh oracle@stby01
rman target / catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB" @/tmp/05_resync_stby.sql
```

**Variant 3b — interactively (typing commands):**

```bash
ssh oracle@stby01
rman target / catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB"
```

```rman
# Pull standby controlfile metadata into the catalog
RMAN> RESYNC CATALOG FROM DB_UNIQUE_NAME 'STBY';
starting full resync of recovery catalog
full resync complete

RMAN> EXIT;
```

#### B.4.4 — Validate STBY in the catalog (on rcat01)

> ⚠️ **Lesson learned 2026-05-04 iter.11:** in 26ai the `RC_SITE` view does **NOT** have `DBID` nor `DB_NAME` columns (only `SITE_KEY`, `DB_KEY`, `DATABASE_ROLE`, `DB_UNIQUE_NAME`). You must JOIN `RC_DATABASE` on `DB_KEY` to display DBID. Selecting `dbid` directly from `rc_site` raises ORA-00904 'invalid identifier'.

```bash
sqlplus -S 'rman_cat/Oracle26ai_LAB!@rcat01:1521/RCATPDB' <<'SQL'
SET HEADING ON FEEDBACK OFF PAGESIZE 50 LINESIZE 150
COLUMN db_unique_name FORMAT A20 HEADING "DB Unique Name"
COLUMN database_role  FORMAT A18 HEADING "DG Role"
COLUMN db_name        FORMAT A12 HEADING "DB Name"
COLUMN dbid           FORMAT 99999999999 HEADING "DBID"

-- JOIN RC_SITE x RC_DATABASE: should return 2 sites with the same DBID
SELECT s.site_key, s.db_unique_name, s.database_role, d.name AS db_name, d.dbid
  FROM rc_site s
  JOIN rc_database d ON s.db_key = d.db_key
 ORDER BY s.db_unique_name;
-- Expected:
-- SITE_KEY  DB_UNIQUE_NAME  DG_ROLE   DB_NAME  DBID
-- --------  --------------  --------  -------  ----------
--    3      PRIM            PRIMARY   PRIM     229119773
--    566    STBY            STANDBY   PRIM     229119773    <- SAME DBID, DIFFERENT db_unique_name

EXIT
SQL
```

> 💡 **Why does RC_DATABASE show 1 row and RC_SITE 2?**
> `RC_DATABASE` is grouped by DBID (i.e. per logical database). `RC_SITE` distinguishes by `db_unique_name` (i.e. per physical instance in the DG configuration).

## ✅ Validation

```bash
# IMPORTANT: single quotes around the connect string (bash '!' history expansion).
sqlplus -S 'rman_cat/Oracle26ai_LAB!@rcat01:1521/RCATPDB' <<'SQL'
SET HEADING ON FEEDBACK OFF PAGESIZE 50

-- Has the catalog been created? Count objects in the entire rman_cat schema.
-- Lesson 2026-05-03 iter.9: in 26ai views have the RCI_ prefix (NOT RC_).
SELECT 'Tables: ' || COUNT(*) FROM user_tables;     -- ~62
SELECT 'Views: ' || COUNT(*) FROM user_views;       -- ~124 RCI_*
SELECT 'Total objects: ' || COUNT(*) FROM user_objects;   -- ~1100+

-- Sample of RCI_* views (RMAN Catalog Internal — 26ai prefix)
SELECT view_name FROM user_views WHERE view_name LIKE 'RCI_%' AND ROWNUM <= 5;
-- RCI_BACKUP_CONTROLFILE, RCI_BACKUP_DATAFILE, RCI_DATABASE...

-- Is PRIM registered? (after REGISTER DATABASE from PRIM)
SELECT name, dbid FROM rc_database;
-- Expected after B.3: 1 row — PRIM visible with its dbid (e.g. 229119773)
-- NOTE: after B.4 (REGISTER STBY) RC_DATABASE will still show 1 row (grouping by DBID)
-- to see both (PRIM + STBY) use RC_SITE — see B.4.4

-- After B.4: RC_SITE should show PRIM + STBY (same DBID, different db_unique_name)
-- NOTE: RC_SITE in 26ai has no DBID/DB_NAME - JOIN RC_DATABASE on DB_KEY (lesson iter.11)
SELECT s.db_unique_name, s.database_role, d.name AS db_name, d.dbid
  FROM rc_site s
  JOIN rc_database d ON s.db_key = d.db_key
 ORDER BY s.db_unique_name;
-- Expected after B.4: 2 rows (PRIM + STBY) with the same DBID

EXIT
SQL
```

## 🔐 Security

| Concern | LAB implementation | In production |
|---|---|---|
| rman_cat password | `$LAB_PASS` from `/root/.lab_secrets` (chmod 600, kickstart-managed) | Oracle Wallet / JCEKS |
| Network connection | Plain TCP/1521 | TCPS (SSL) |
| RECOVERY_CATALOG_OWNER user | Full access to the catalog | OK (this is the standard) |
| Backup of rman_cat password | `/root/.lab_secrets` chmod 600 (manual) | Wallet + auto-rotate |

## 📦 What else does the catalog give us

### Extended retention (vs controlfile-only)

```sql
-- Controlfile RECORD_KEEP_TIME (default 7 days)
ALTER SYSTEM SET CONTROL_FILE_RECORD_KEEP_TIME=14 SCOPE=BOTH;
-- After expiration RMAN loses metadata if there is no catalog

-- With the catalog we keep metadata as long as we want (DBA decision)
CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 90 DAYS;  -- on PRIM
```

### Stored Scripts (centralized procedures)

```rman
RMAN> CREATE SCRIPT weekly_full_backup
{
  BACKUP DATABASE
    PLUS ARCHIVELOG
    DELETE INPUT
    TAG 'weekly_l0'
    FORMAT '/mnt/rman_bck/full/full_%U';
};

-- From any client
RMAN> RUN { EXECUTE SCRIPT weekly_full_backup; }
```

### Cross-database reports

```sql
-- Backups across all registered databases
SELECT db_name, backup_type, count(*), sum(bytes)/1024/1024 AS size_mb
  FROM rc_backup_set
  GROUP BY db_name, backup_type
  ORDER BY 1, 2;
```

## 🚧 Troubleshooting

| Problem | Resolution |
|---|---|
| `RMAN-04004 connection error` | Check `tnsping rcat01:1521/RCATPDB` from PRIM |
| `RMAN-20002 target database already registered` | OK — already done, you can `UNREGISTER DATABASE` and `REGISTER` again |
| `ORA-12541 TNS:no listener` | `lsnrctl status` on rcat01, check that the listener is running |
| `ORA-01017 invalid username/password` | `rman_cat` password source-of-truth: `01_create_catalog_schema.sql` |
| RCATPDB service not visible | `ALTER SYSTEM REGISTER;` in RCATPDB as sys |

## ⏭️ Next step

Sprint 1 COMPLETED (steps 1-3 + 3a REGISTER PRIM + 3b REGISTER STBY).

**Sprint 1 stages:** VM Preparation → DB Install + Auto-Start → Catalog Setup → REGISTER PRIM (Iter.10) → REGISTER STBY (Iter.11).

Move on to Sprint 2:

[06_Backup_Policy.md](06_Backup_Policy.md) — backup policy (full/incremental/archivelog cycles).
