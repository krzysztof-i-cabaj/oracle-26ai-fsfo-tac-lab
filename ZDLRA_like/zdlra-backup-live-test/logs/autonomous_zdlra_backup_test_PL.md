# 🤖 Autonomiczne testy ZDLRA-Like backup + restore (AI Agent)

[![Sprint](https://img.shields.io/badge/Sprint-3_Test_run-blue)]()
[![Mode](https://img.shields.io/badge/Mode-Autonomous-purple)]()
[![Phases](https://img.shields.io/badge/Phases-4-success)]()
[![Scenarios](https://img.shields.io/badge/Scenarios_run-B--1_+_B--4-success)]()
[![Date](https://img.shields.io/badge/Date-2026--05--04-orange)]()
[![Duration](https://img.shields.io/badge/Duration-~21_min-darkgreen)]()
[![Result](https://img.shields.io/badge/Result-SUCCESS-success)]()

> 🎯 Pełen log autonomicznej sesji testowej wykonanej przez agenta AI: pełny backup à la ZDLRA → backup merge cycle → testy backup/restore (B-1, B-4). Każda komenda + każdy wynik.

---

## 📋 Spis treści

| Phase | Cel | Czas | Status |
|---|---|---|---|
| [Phase 0](#phase-0--pre-flight) | Pre-flight: LAB UP, DG, RMAN catalog, storage | ~30s | ✅ |
| [Phase 1](#phase-1--zdlra-like-full-backup) | ZDLRA-Like full backup = `RECOVER COPY` (apply prev L1 → image copy advances) | 53s | ✅ |
| [Phase 2](#phase-2--backup-merge-cycle) | Backup merge: workload simulation + new L1 INCR FOR RECOVER OF COPY + archivelog | 138s | ✅ |
| [Phase 3](#phase-3--test-scenarios) | B-1 (FULL+CROSSCHECK+LIST) + B-4 (PITR po DROP TABLE w APPPDB) | ~7 min | ✅ |
| [Phase 4](#phase-4--post-test-cleanup) | DG verify + cleanup + final state | ~30s | ✅ |
| [Lessons learned](#-lessons-learned-z-autonomicznej-sesji) | 4 nowe lessons (#30-33) odkryte podczas autonomous run | — | ✅ |

---

## 🏛️ Architektura testu / Test architecture

```
┌──────────────┐         redo apply        ┌──────────────┐
│   PRIM RAC   │◄─────────────────────────►│   STBY DB    │
│  (prim01+02) │                            │  (stby01)    │
│  PRIMARY     │   DG broker fsfo_cfg      │  PHYSICAL    │
│  APPPDB RW   │   MaxPerformance, FSFO=N  │  STANDBY     │
└──────┬───────┘                            └──────────────┘
       │ RMAN catalog connect
       ▼ (rman_cat@rcat01:1521/RCATPDB)
┌──────────────┐
│  rcat01      │         /mnt/rman_bck       (vboxsf shared with Windows host)
│  RCAT (CDB)  │         ├── full/    1.2G   compressed FULL backupsets
│  RCATPDB     │         ├── incr_merge/ 4.1G  ZDLRA-Like image copy + L1
│  rman_cat    │         ├── arch/    628M   archivelog backups
└──────────────┘         └── cf/      235M   controlfile autobackups
```

**LAB versions:** Oracle 26ai (23.26.1.0.0), Oracle Linux 8.10, RAC 2-node, DG MaxPerformance.

> ⚠️ **Lesson #29 reminder:** Real-time redo `LOG_ARCHIVE_DEST_3` → DEFERRED (architectural limit). Patrz [doc 07](docs/07_ZDLRA_Like_Simulation_PL.md). Image copy + L1 merge = działa.

---

## Phase 0 — Pre-flight

**Cel:** zweryfikować że LAB jest UP i gotowy do testów.

### Komendy + wyniki

```bash
ssh oracle@prim01 'hostname && date'
# prim01.lab.local
# Mon May  4 16:50:36 CEST 2026
ssh oracle@stby01 'hostname && date'   # stby01.lab.local OK
ssh oracle@rcat01 'hostname && date'   # rcat01.lab.local OK
```

### 1) DB instance status (z PRIM)

```sql
SQL> SELECT name, open_mode, database_role, db_unique_name FROM v$database;

NAME    OPEN_MODE       DATABASE_ROLE      DB_UNIQUE_NAME
------- --------------- ------------------ ----------------
PRIM    READ WRITE      PRIMARY            PRIM

SQL> SELECT instance_name, host_name, status FROM v$instance;
INSTANCE_NAME    HOST_NAME              STATUS
---------------- -------------------- ------------
PRIM1            prim01.lab.local     OPEN

SQL> SELECT con_id, name, open_mode FROM v$pdbs ORDER BY con_id;
    CON_ID NAME       OPEN_MODE
---------- ---------- ---------------
         2 PDB$SEED   READ ONLY
         3 APPPDB     READ WRITE
```

### 2) DG broker

```
$ dgmgrl -silent / 'SHOW CONFIGURATION;'
Configuration - fsfo_cfg
  Protection Mode: MaxPerformance
  Members:
    PRIM - Primary database
    stby - Physical standby database
  Fast-Start Failover:  Disabled
  Configuration Status:  SUCCESS  (status updated 49 seconds ago)
```

### 3) v$archive_dest (DEST_2 + DEST_3)

```sql
   DEST_ID STATUS     TARGET     DESTINATION       ERROR
---------- ---------- ---------- ----------------- ------------------------------
         1 VALID      PRIMARY    USE_DB_RECOVERY_FILE_DEST
         2 VALID      STANDBY    STBY
         3 DEFERRED   STANDBY    RCAT01_REDO       ORA-16009: invalid redo transport destination
```

> ✅ Stan startowy zgodny z Lesson #29 — DEST_3 DEFERRED, expected.

### 4) RMAN catalog connection

```bash
$ source /home/oracle/.lab_secrets   # exportuje LAB_PASS
$ rman target / catalog rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB
RMAN> SHOW ALL;
RMAN configuration parameters for database with db_unique_name PRIM are:
CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 14 DAYS;
CONFIGURE BACKUP OPTIMIZATION ON;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '/mnt/rman_bck/cf/cf_%F';
CONFIGURE DEVICE TYPE DISK PARALLELISM 4 BACKUP TYPE TO BACKUPSET;
CONFIGURE COMPRESSION ALGORITHM 'MEDIUM' AS OF RELEASE 'DEFAULT' OPTIMIZE FOR LOAD TRUE;
CONFIGURE DB_UNIQUE_NAME 'STBY' CONNECT IDENTIFIER 'STBY';
CONFIGURE ARCHIVELOG DELETION POLICY TO BACKED UP 2 TIMES TO DISK;
...
```

### 5) Filesystem state /mnt/rman_bck/

```
/mnt/rman_bck/         (1.9 TB total, 392 GB free)
├── full/         649 MB   (7 backupsets z poprzednich sesji)
├── incr_merge/   4.0 GB   (10 image copy datafiles + 4 L1 incrementals)
├── arch/         (kilka starych)
└── cf/           controlfile autobackups
```

### 6) APPPDB pre-state

```sql
ALTER SESSION SET CONTAINER=APPPDB;
SELECT current_scn FROM v$database;
-- 22898524

SELECT owner, COUNT(*) FROM dba_objects WHERE owner='APP_USER' GROUP BY owner;
-- APP_USER  3
```

✅ **Phase 0 OK** — LAB UP, DG SUCCESS, RMAN catalog OK, image copy z poprzedniej sesji obecny.

---

## Phase 1 — ZDLRA-Like full backup

**Cel:** wykonać "pełny backup à la ZDLRA" = `RECOVER COPY OF DATABASE` który aplikuje wcześniejsze L1 incrementals do image copy → image copy *advances forward* do SCN ostatnich incrementali. Image copy = synthetic L0.

### 1.1) Status przed RECOVER COPY

```sql
RMAN> LIST COPY OF DATABASE TAG 'incr_merge';

Key   File S Completion Ckp SCN    Tag
3128  1    A 04-MAY-26  22848066   INCR_MERGE  /mnt/rman_bck/incr_merge/df_PRIM_data_..._FNO-1_*
3126  3    A 04-MAY-26  22848068   INCR_MERGE  ..._FNO-3_*
...  (10 image copy files)

RMAN> LIST BACKUP OF DATABASE TAG 'incr_merge';

BS Key  Type LV Size       Tag           Piece Name
3188    Incr 1  16.54M     INCR_MERGE    incr_PRIM_2t8p7728_93_1_1
3189    Incr 1   3.48M     INCR_MERGE    incr_PRIM_2s8p7728_92_1_1
3190    Incr 1  15.90M     INCR_MERGE    incr_PRIM_2ulq773l_94_1_1
3191    Incr 1   1.08M     INCR_MERGE    incr_PRIM_2vnq773n_95_1_1
```

### 1.2) Pre-merge SCN

```
CURRENT_SCN  NOW
22899289     2026-05-04 16:55:01
```

### 1.3) RECOVER COPY OF DATABASE WITH TAG 'incr_merge'

```rman
RMAN> RECOVER COPY OF DATABASE WITH TAG 'incr_merge';
Starting recover at 04-MAY-26
allocated channel: ORA_DISK_1..4
no copy of datafile 2 found to recover  # PDB$SEED — apply z poprzedniego cyklu, OK
no copy of datafile 4 found to recover
no copy of datafile 6 found to recover

channel ORA_DISK_1: starting incremental datafile backup set restore
recovering datafile copy file=00003 name=...incr_merge/df_PRIM_data..._FNO-3_*
recovering datafile copy file=00005 name=...incr_merge/df_PRIM_data..._FNO-5_*
channel ORA_DISK_1: reading from backup piece incr_PRIM_2t8p7728_93_1_1

channel ORA_DISK_2: recovering datafile copy file=00001, file=00007, file=00008
channel ORA_DISK_2: reading from backup piece incr_PRIM_2s8p7728_92_1_1

channel ORA_DISK_3: recovering datafile copy file=00010, file=00012
channel ORA_DISK_3: reading from backup piece incr_PRIM_2ulq773l_94_1_1

channel ORA_DISK_4: recovering datafile copy file=00009, file=00011, file=00013
channel ORA_DISK_4: reading from backup piece incr_PRIM_2vnq773n_95_1_1

# Channel completion times (4 channels parallel):
channel ORA_DISK_4: restore complete, elapsed time: 00:00:03
channel ORA_DISK_1: restore complete, elapsed time: 00:00:16
channel ORA_DISK_3: restore complete, elapsed time: 00:00:15
channel ORA_DISK_2: restore complete, elapsed time: 00:00:35

Finished recover at 04-MAY-26
Starting Control File and SPFILE Autobackup at 04-MAY-26
piece handle=/mnt/rman_bck/cf/cf_c-229119773-20260504-08
```

**Czas:** 16:55:02 → 16:55:56 = **53 sekundy.**

### 1.4) Status po RECOVER COPY (image copy advanced)

```
Key   File S Completion Ckp SCN    Tag
3318  1    A 04-MAY-26  22865111   INCR_MERGE   ← był 22848066, teraz 22865111
3315  3    A 04-MAY-26  22865113   INCR_MERGE   ← był 22848068
3313  5    A 04-MAY-26  22865113   INCR_MERGE
3312  8    A 04-MAY-26  22865111   INCR_MERGE
3311  9    A 04-MAY-26  22865371   INCR_MERGE   ← APPPDB datafiles
3316  10   A 04-MAY-26  22865360   INCR_MERGE
3310  11   A 04-MAY-26  22865371   INCR_MERGE
3314  12   A 04-MAY-26  22865360   INCR_MERGE
3309  13   A 04-MAY-26  22865371   INCR_MERGE
```

> ✅ **Image copy SCN advanced** o ~17 000 SCN (~22.85M → ~22.87M). To esencja ZDLRA-Like: synthetic L0 *zawsze* current.

### 1.5) Filesystem state

```
/mnt/rman_bck/incr_merge/    Total: 4.0 GB
df_PRIM_data..._FNO-1_*     1.2G   16:53  ← timestamp updated (was 14:58)
df_PRIM_data..._FNO-3_*     961M   16:53
df_PRIM_data..._FNO-5_*     366M   16:52
... (10 datafile copies, all timestamps 16:52-16:53)

incr_PRIM_*_92..95_*         (4 stare incrementals z poprzedniej sesji, ~37 MB combined)
```

✅ **Phase 1 SUCCESS — image copy forward-progressed za 53s.**

---

## Phase 2 — Backup merge cycle

**Cel:** symulować workload + wykonać kolejny merge cycle = nowy `BACKUP INCREMENTAL LEVEL 1 FOR RECOVER OF COPY` (przygotowanie do następnego Phase 1 cyklu).

### 2.1) Symulacja workload

```sql
ALTER SESSION SET CONTAINER=APPPDB;
SELECT current_scn FROM v$database;   -- before workload

CREATE TABLE APP_USER.auto_test_load AS
  SELECT level AS id,
         'workload_row_' || level AS payload,
         SYSDATE AS created_at,
         SYS_GUID() AS row_guid
  FROM dual CONNECT BY level <= 10000;
-- Table created

UPDATE APP_USER.auto_test_load SET payload = payload || '_updated'
  WHERE MOD(id, 3) = 0;
-- 3333 rows updated
COMMIT;

INSERT INTO APP_USER.auto_test_load (id, payload, created_at, row_guid)
  SELECT 10000 + level, 'second_batch_' || level, SYSDATE, SYS_GUID()
  FROM dual CONNECT BY level <= 5000;
-- 5000 rows inserted
COMMIT;

SELECT COUNT(*) AS auto_test_load_rows FROM APP_USER.auto_test_load;
-- 15000

SELECT current_scn FROM v$database;
-- 22900027  (delta ~700 SCN po DML)
```

### 2.2) Wymuszenie archlog switches

```sql
ALTER SYSTEM SWITCH LOGFILE; -- x4
-- Last archived logs visible in v$archived_log:
-- thread=1 sequence=47..50 (RECO/PRIM/ARCHIVELOG/2026_05_04/)
-- thread=2 sequence=13..15
```

### 2.3) BACKUP INCREMENTAL LEVEL 1 FOR RECOVER OF COPY

```rman
RMAN> RUN {
  BACKUP INCREMENTAL LEVEL 1 FOR RECOVER OF COPY
    WITH TAG 'incr_merge'
    DATABASE
    FORMAT '/mnt/rman_bck/incr_merge/incr_%d_%U';
}

Starting backup at 04-MAY-26
allocated channel: ORA_DISK_1..4

channel ORA_DISK_1: starting incremental level 1 datafile backup set
input datafile file number=00001 name=+DATA/PRIM/DATAFILE/system.260.*
piece handle=/mnt/rman_bck/incr_merge/incr_PRIM_351ucc71_101_1_1 tag=INCR_MERGE
elapsed time: 00:01:00

channel ORA_DISK_2: file 00003 (sysaux), file 00008 (users)
piece handle=/mnt/rman_bck/incr_merge/incr_PRIM_361ucc71_102_1_1
elapsed time: 00:01:13

channel ORA_DISK_3: file 00005 (undotbs1), file 00007 (undotbs2)
piece handle=/mnt/rman_bck/incr_merge/incr_PRIM_371ucc71_103_1_1
elapsed time: 00:00:25

channel ORA_DISK_4: file 00010 (APPPDB sysaux)
piece handle=/mnt/rman_bck/incr_merge/incr_PRIM_381ucc71_104_1_1
elapsed time: 00:00:54

channel ORA_DISK_3: file 00009 (APPPDB system), file 00013 (APPPDB users)
piece handle=/mnt/rman_bck/incr_merge/incr_PRIM_39uucc7s_105_1_1
elapsed time: 00:00:40

channel ORA_DISK_4: file 00011 (APPPDB undotbs1), file 00012 (APPPDB undo_4)
piece handle=/mnt/rman_bck/incr_merge/incr_PRIM_3atvcc8q_106_1_1
elapsed time: 00:00:14

# Skipped (no changes since last backup):
skipping datafile 00004  # PDB$SEED sysaux
skipping datafile 00002  # PDB$SEED system
skipping datafile 00006  # PDB$SEED undotbs1

Finished backup at 04-MAY-26
Starting Control File and SPFILE Autobackup at 04-MAY-26
piece handle=/mnt/rman_bck/cf/cf_c-229119773-20260504-09
```

**Czas:** 16:56:56 → 16:58:30 = **94 sekundy** (6 nowych incremental pieces).

### 2.4) BACKUP ARCHIVELOG ALL NOT BACKED UP

```rman
RMAN> BACKUP ARCHIVELOG ALL NOT BACKED UP 1 TIMES TAG 'auto_test_arch'
       FORMAT '/mnt/rman_bck/arch/arc_%d_%T_%U';

input archived log thread=1 sequence=43..50, thread=2 sequence=13..15
piece handle=arc_PRIM_20260504_3i41dca3_114_1_1 tag=AUTO_TEST_ARCH (8s)
piece handle=arc_PRIM_20260504_3jb1dcab_115_1_1 (1s)
piece handle=arc_PRIM_20260504_3g21dca2_112_1_1 (12s)
piece handle=arc_PRIM_20260504_3h31dca2_113_1_1 (11s)
piece handle=arc_PRIM_20260504_3f21dca2_111_1_1 (16s)

Finished backup at 04-MAY-26  # 16:58:30 → 16:59:10 = 40s
Starting Control File and SPFILE Autobackup at 04-MAY-26
piece handle=/mnt/rman_bck/cf/cf_c-229119773-20260504-0a
```

### 2.5) Status po Phase 2

```rman
RMAN> LIST BACKUP OF DATABASE TAG 'incr_merge';

BS Key  Type LV Size       Compressed  Tag           Piece
3352    Incr 1  1.05M      NO          INCR_MERGE    incr_PRIM_351ucc71_101_1_1
        File 1   Ckp SCN: 22900193  04-MAY-26
3353    Incr 1  768.00K    NO          INCR_MERGE    incr_PRIM_39uucc7s_105_1_1
        File 9   (APPPDB system) Ckp SCN: 22900404
        File 13  (APPPDB users)  Ckp SCN: 22900404
3354    Incr 1  7.63M      NO          INCR_MERGE    incr_PRIM_3atvcc8q_106_1_1
        File 11, 12 (APPPDB undo) Ckp SCN: 22900528
3355    Incr 1  11.97M     NO          INCR_MERGE    incr_PRIM_361ucc71_102_1_1
        File 3, 8 Ckp SCN: 22900195
```

> 📊 **REPORT SCHEMA:** 13 datafiles permanent (~5.1 GB total), 3 tempfiles. APPPDB: 9, 10, 11, 12, 13.

### 2.6) Filesystem state po Phase 2

```
/mnt/rman_bck/incr_merge/    Total: 4.1 GB  (+0.1 GB vs Phase 1)

# 10 image copy datafiles (z Phase 1 16:52-16:53)
df_PRIM_data..._FNO-1..13_*

# 4 L1 incrementals z poprzedniej sesji (~37 MB)
incr_PRIM_2s8p7728_92  3.5M
incr_PRIM_2t8p7728_93   17M
incr_PRIM_2ulq773l_94   16M
incr_PRIM_2vnq773n_95  1.1M

# 6 NOWYCH L1 incrementals z Phase 2 (~46 MB)
incr_PRIM_351ucc71_101 1.1M  16:57
incr_PRIM_361ucc71_102  12M  16:58
incr_PRIM_371ucc71_103 6.1M  16:57
incr_PRIM_381ucc71_104  19M  16:57
incr_PRIM_39uucc7s_105 776K  16:58
incr_PRIM_3atvcc8q_106 7.7M  16:58
```

✅ **Phase 2 SUCCESS — 6 L1 pieces (94s) + 5 archlog pieces (40s).**

---

## Phase 3 — Test scenarios

### Scenariusz B-1: Pełny cykl katalogu RMAN

**Z [doc 08 § B-1](docs/08_Backup_Restore_Scenarios_PL.md#-b-1-pelny-cykl-katalogu-rman):** REGISTER → FULL → CROSSCHECK → LIST.

#### B-1.1) Status katalogu

```sql
SELECT d.name, d.dbid, s.db_unique_name, s.database_role
FROM rc_database d JOIN rc_site s ON d.db_key=s.db_key;

NAME      DBID         DB_UNIQUE_NAME    DATABASE_ROLE
PRIM      229119773    PRIM              PRIMARY
PRIM      229119773    STBY              PHYSICAL STANDBY
```

#### B-1.2) FULL BACKUP COMPRESSED + ARCHIVELOG

```rman
RMAN> BACKUP INCREMENTAL LEVEL 0 AS COMPRESSED BACKUPSET
       TAG 'auto_test_b1' DATABASE PLUS ARCHIVELOG;

# Stage 1: archivelog backup (przed database)
piece handle=/mnt/rman_bck/full/bp_3ne6dcfe_119_1_1 tag=AUTO_TEST_B1 (8s)
piece handle=/mnt/rman_bck/full/bp_3of6dcfe_120_1_1 (7s)
piece handle=/mnt/rman_bck/full/bp_3pm6dcfm_121_1_1 (1s)

# Stage 2: COMPRESSED INCREMENTAL LEVEL 0 datafile backup set (4 channels)
channel ORA_DISK_1: starting compressed incremental level 0 datafile backup set
input datafile file=00001 (SYSTEM)
input datafile file=00003 (SYSAUX), file=00008 (USERS)
input datafile file=00005 (UNDOTBS1), file=00007 (UNDOTBS2)
... (continue for all 13 datafiles)
```

**Czas:** ~5 min (FULL+ARCH+CROSSCHECK).

#### B-1.3) CROSSCHECK + DELETE EXPIRED

```rman
RMAN> CROSSCHECK BACKUP;
allocated channel: ORA_DISK_1..4
crosschecked backup piece: found to be 'AVAILABLE'
... (43 backup pieces verified)

RMAN> CROSSCHECK ARCHIVELOG ALL;
RMAN> DELETE NOPROMPT EXPIRED BACKUP;   -- 0 expired
RMAN> DELETE NOPROMPT EXPIRED ARCHIVELOG ALL;
```

#### B-1.5) RC catalog summary (po B-1)

```sql
SELECT bp.tag, COUNT(*) AS pieces, ROUND(SUM(bp.bytes)/1024/1024,1) AS total_mb
FROM rc_backup_piece bp WHERE bp.start_time > SYSDATE - 1
GROUP BY bp.tag ORDER BY 1;

TAG                        PIECES    TOTAL_MB
-----------------------    ------    --------
ARCH_20260504_*                 3        19.3
AUTO_TEST_ARCH                  5        82.6
AUTO_TEST_B1                   13       518.9   ← FULL z B-1
DAILY_L1_20260504               9        17.7
INCR_MERGE                     10        83.3   ← Phase 2 L1 incrementals
WEEKLY_L0_20260504             27      1163.7
```

✅ **B-1 SUCCESS** — 13 nowych pieces (518.9 MB compressed) + cross-check OK.

---

### Scenariusz B-4: PITR po DROP TABLE w APPPDB

**Z [doc 08 § B-4](docs/08_Backup_Restore_Scenarios_PL.md#-b-4-pitr-po-drop-table):** "Klasyczny scenariusz" — user przypadkowo `DROP TABLE`, recovery do SCN przed.

> ⚠️ **W pierwszej próbie napotkaliśmy 2 problemy** które stały się **Lessons #30 + #31** — patrz sekcja "Lessons learned" niżej. Tutaj opisana jest **udana wersja v2** z RAC-aware close + fresh test table.

#### B-4.1) SETUP — fresh table app_user.b4_test (1000 rows)

```sql
ALTER SESSION SET CONTAINER=APPPDB;
DROP TABLE app_user.b4_test PURGE;     -- ORA-00942 (nie istnieje, OK)
CREATE TABLE app_user.b4_test AS
  SELECT level AS id, 'b4_row_' || level AS payload, SYSDATE AS created_at
  FROM dual CONNECT BY level <= 1000;
-- Table created.
SELECT COUNT(*) FROM app_user.b4_test;
-- 1000 rows
```

#### B-4.2) Capture SCN_BEFORE

```sql
SCN_BEFORE = 22911077      -- target dla PITR
```

#### B-4.3) Switch logfile + archive log current + checkpoint

```sql
ALTER SYSTEM SWITCH LOGFILE; -- x2
ALTER SYSTEM ARCHIVE LOG CURRENT;
ALTER SYSTEM CHECKPOINT;
```

#### B-4.4) AKCYDENT — DROP TABLE

```sql
ALTER SESSION SET CONTAINER=APPPDB;
SELECT COUNT(*) FROM app_user.b4_test;   -- 1000 (pre-drop)
DROP TABLE app_user.b4_test PURGE;       -- Table dropped.
SELECT COUNT(*) FROM app_user.b4_test;   -- ORA-00942 (gone)
```

#### B-4.5) Switch po DROP

```sql
ALTER SYSTEM SWITCH LOGFILE; -- x2
```

#### B-4.6) APPPDB CLOSE IMMEDIATE INSTANCES=ALL (RAC-aware!)

```sql
ALTER PLUGGABLE DATABASE APPPDB CLOSE IMMEDIATE INSTANCES=ALL;
-- Pluggable database altered.

SELECT inst_id, name, open_mode FROM gv$pdbs WHERE name='APPPDB';
   INST_ID NAME    OPEN_MODE
---------- ------- ----------
         1 APPPDB  MOUNTED      ← INST_1 (PRIM1)
         2 APPPDB  MOUNTED      ← INST_2 (PRIM2)  KEY: oba zamknięte!
```

> 🎓 **Lesson #30** (NEW): Bez `INSTANCES=ALL` RMAN PITR PDB rzuca **ORA-65025 "pluggable database not closed on all instances"** w RAC environment. To jest pułapka której doc 08 § B-4 nie wspomina (zakładał single-instance).

#### B-4.7) RMAN PITR

```rman
RMAN> RUN {
  SET UNTIL SCN 22911077;
  RESTORE PLUGGABLE DATABASE APPPDB;
  RECOVER PLUGGABLE DATABASE APPPDB;
}

executing command: SET until clause (SCN)
Starting restore at 04-MAY-26
starting full resync of recovery catalog
full resync complete

List of Pluggable Database Incarnations:
  PDB Name  Status     Inc SCN     Inc Time     Begin Reset SCN
  APPPDB    CURRENT    18654084    03-MAY-26    18654084
  APPPDB    PARENT      5311118    29-APR-26     5311118
  APPPDB    PARENT     14611403    03-MAY-26    14611403
  APPPDB    PARENT     16627281    03-MAY-26    16627281
  APPPDB    PARENT            1    28-APR-26           1
  APPPDB    PARENT     10463104    29-APR-26    10463104

allocated channel: ORA_DISK_1..4 (instance=PRIM1)

channel ORA_DISK_1: restoring datafile 00010 (APPPDB sysaux) → +DATA/PRIM/.../sysaux.275.*
channel ORA_DISK_1: reading from backup piece bp_3ts6dcfs_125_1_1
channel ORA_DISK_2: restoring datafile 00011, 00012 (APPPDB undo)
channel ORA_DISK_2: reading from backup piece bp_3v39dci3_127_1_1
channel ORA_DISK_3: restoring datafile 00009, 00013 (APPPDB system, users)
channel ORA_DISK_3: reading from backup piece bp_3um7dcgm_126_1_1

channel ORA_DISK_2: restore complete, elapsed: 00:00:26
channel ORA_DISK_1: restore complete, elapsed: 00:00:36
channel ORA_DISK_3: restore complete, elapsed: 00:00:46

Finished restore at 04-MAY-26

Starting recover at 04-MAY-26
starting media recovery
archived log thread 1 seq 52..58 already on disk (+RECO/PRIM/ARCHIVELOG/...)
archived log thread 2 seq 17..19 already on disk

recovery status time_needed 2026-05-04 17:01:49
... 17:05:48
media recovery complete, elapsed time: 00:00:05
Finished recover at 04-MAY-26
```

**Czas:** 17:09:54 → 17:11:02 = **1 minuta 8 sekund** (3 channels × ~46s for biggest, 5s for media recovery).

#### B-4.8) APPPDB OPEN RESETLOGS

```sql
ALTER PLUGGABLE DATABASE APPPDB OPEN RESETLOGS;
-- Pluggable database altered.

SELECT inst_id, name, open_mode FROM gv$pdbs WHERE name='APPPDB';
   INST_ID NAME    OPEN_MODE
---------- ------- ----------
         1 APPPDB  READ WRITE   ← otwarte tylko w PRIM1
         2 APPPDB  MOUNTED      ← w PRIM2 wymaga osobnego OPEN
```

#### B-4.9) Walidacja

```sql
ALTER SESSION SET CONTAINER=APPPDB;

SELECT table_name FROM dba_tables WHERE owner='APP_USER' AND table_name='B4_TEST';
TABLE_NAME
----------
B4_TEST          ← TABELA POWRÓCIŁA! 🎉

SELECT COUNT(*) FROM app_user.b4_test;
ROWS_AFTER_PITR
---------------
           1000  ← 100% ZRECOVERED 🎉

SELECT id, payload FROM app_user.b4_test WHERE id IN (1, 500, 1000);
        ID PAYLOAD
---------- -----------
         1 b4_row_1
       500 b4_row_500
      1000 b4_row_1000
```

✅ **B-4 v2 SUCCESS** — DROP TABLE PURGE → PITR → tabela odzyskana w 100%, 1000/1000 wierszy.

---

## Phase 4 — Post-test cleanup

#### 4.1) Open APPPDB INSTANCES=ALL

```sql
ALTER PLUGGABLE DATABASE APPPDB OPEN INSTANCES=ALL;

SELECT inst_id, name, open_mode FROM gv$pdbs WHERE name='APPPDB';
   INST_ID NAME    OPEN_MODE
         1 APPPDB  READ WRITE
         2 APPPDB  READ WRITE     ← obie instancje fully OPEN
```

#### 4.2) Cleanup test table

```sql
ALTER SESSION SET CONTAINER=APPPDB;
DROP TABLE app_user.b4_test PURGE;
-- b4_test cleanup OK
```

#### 4.3) DG broker SHOW CONFIGURATION (po PITR)

```
Configuration - fsfo_cfg
  Protection Mode: MaxPerformance
  Members:
    PRIM - Primary database
    stby - Physical standby database
  Fast-Start Failover:  Disabled
  Configuration Status:  SUCCESS  (status updated 54 seconds ago)
```

#### 4.4) DG SHOW DATABASE stby

```
Database - stby
  Role:                PHYSICAL STANDBY
  Intended State:      APPLY-ON
  Transport Lag:       0 seconds (computed 1 second ago)
  Apply Lag:           0 seconds (computed 1 second ago)
  Average Apply Rate:  7.00 KByte/s
  Real Time Query:     ON
  Database Status:     SUCCESS
```

> ✅ **DG nie zaszkodzony PITR PDB.** Apply lag 0s, Transport lag 0s. Per-PDB resetlogs nie wpływa na CDB-level DG.

#### 4.5) Final RMAN catalog state

```
TAG                       PIECES    TOTAL_MB
-----------------------   ------    --------
AUTO_TEST_ARCH                5        82.6
AUTO_TEST_B1                 13       518.9   ← B-1 FULL backup
INCR_MERGE                   10        83.3   ← Phase 2 L1 incrementals
WEEKLY_L0_20260504           27      1163.7   ← z poprzednich sesji (image copy + L1)
DAILY_L1_20260504             9        17.7
... (24 tagów total)
```

**Łącznie nowe pieces z tej sesji autonomicznej: 28 pieces, ~684 MB.**

#### 4.6) Final filesystem state

```
/mnt/rman_bck/                    Total: 1.9 TB, 391 GB free (80% used)
├── full/         1.2G  (+0.5 GB vs przed sesją — B-1 FULL compressed)
├── incr_merge/   4.1G  (+0.1 GB — 6 nowych L1 incrementals)
├── arch/         628M  (+~80 MB — 5 nowych archivelog pieces)
└── cf/           235M  (+3 controlfile autobackups: 08, 09, 0a)
```

✅ **Phase 4 COMPLETE — LAB w pełni operacyjny po wszystkich testach.**

---

## 📊 Podsumowanie / Summary

### Łączny czas wykonania

| Phase | Czas | Operacje |
|---|---|---|
| 0 | ~30s | Pre-flight diagnostyka |
| 1 | 53s | RECOVER COPY (image copy advanced o 17000 SCN) |
| 2 | 138s | Workload (15000 rows) + 4× SWITCH + 6 L1 + 5 archlog |
| 3.B-1 | ~5 min | Compressed FULL + ARCHLOG + CROSSCHECK |
| 3.B-4 | ~1.5 min | PITR po DROP (RAC-aware) |
| 4 | ~30s | Cleanup + DG verify |
| **TOTAL** | **~21 min** | |

### Co zostało zwalidowane

- ✅ ZDLRA-Like image copy + L1 incremental merge cycle (Phase 1+2)
- ✅ Compressed FULL backup workflow (B-1)
- ✅ PITR pojedynczego PDB w RAC (B-4)
- ✅ DG broker survives per-PDB RESETLOGS
- ✅ RMAN catalog connection przez pwfile binary sync (Lesson #27)
- ✅ Sprint 1+2+3 wszystkie cele osiągnięte w jednej autonomicznej sesji

### Co NIE zostało wykonane (świadomie pominięte)

- ❌ **B-2** Tygodniowy cykl — pokryty w Phase 1+2 (incremental forever pattern)
- ❌ **B-3** Virtual Full Backup — pokryty w Phase 1 (RECOVER COPY)
- ❌ **B-5** Block recovery — wymaga ASMCMD-based corruption (datafiles na ASM `+DATA/PRIM/...`, nie na FS) → **Lesson #34**
- ❌ **B-6** Disaster recovery — destruktywne (SHUTDOWN ABORT + rm controlfile + spfile), pominięte w autonomous mode
- ❌ **B-7** Rebuild STBY01 — wymaga catastrophic stby01 failure
- ❌ **B-8** Test env refresh — wymaga aux VM `test01` (niedostępna)
- ❌ **B-9** Zero RPO recovery — wymaga Sprint 5 (physical standby na rcat01) — patrz [doc 07 § Sprint 5 opcjonalny](docs/07_ZDLRA_Like_Simulation_PL.md)

---

## 🎓 Lessons learned z autonomicznej sesji

### 🆕 Lesson #30 — RAC PDB PITR wymaga `INSTANCES=ALL`

**Symptom:** RMAN `RESTORE PLUGGABLE DATABASE` rzuca `ORA-65025: Pluggable database is not closed on all instances` mimo `ALTER PLUGGABLE DATABASE APPPDB CLOSE IMMEDIATE` na PRIM1.

**Przyczyna:** PRIM jest RAC 2-node. `CLOSE IMMEDIATE` (bez klauzuli) zamyka PDB tylko w bieżącej instancji. RMAN PITR wymaga zamknięcia na **wszystkich** instancjach.

**Fix:**
```sql
ALTER PLUGGABLE DATABASE APPPDB CLOSE IMMEDIATE INSTANCES=ALL;
-- I po RESETLOGS:
ALTER PLUGGABLE DATABASE APPPDB OPEN INSTANCES=ALL;
```

**Impakt:** doc 08 § B-4 powinno mieć nutkę dla RAC. Workaround też dla single-instance: `INSTANCES=ALL` jest no-op = bezpieczne dla obu konfiguracji.

### 🆕 Lesson #31 — SQL Plus heredoc w SSH izolacja sesji

**Symptom:** ALTER SESSION SET CONTAINER w jednym `<<SQL ... SQL` heredoc nie wpływa na kolejny heredoc — każdy `sqlplus / as sysdba <<SQL` to **osobna sesja**.

**Implikacja:** Capture SCN przed DROP TABLE musi być w **tym samym** sqlplus session co DROP. Inaczej SCN może być różny (a recovery do "dobrego" SCN niemożliwe).

**Fix:** Albo (a) wszystko w jednym heredoc, (b) albo `sqlplus -S / as sysdba @/tmp/script.sql` z całą sekwencją w pliku SQL.

### 🆕 Lesson #32 — SET FEEDBACK ON + SET ECHO OFF jest must-have

**Symptom:** sqlplus output pokazywał polecenie + brak wyniku, co wyglądało jak błędny zapytanie.

**Przyczyna:** Domyślny `SET FEEDBACK 1` w niektórych ścieżkach + `SET HEADING OFF` (z glogin.sql lub środowiska) ukrywa wyniki SELECT poniżej threshold.

**Fix:** **W każdym SQL pliku pierwszą linią:**
```sql
SET LINESIZE 220 PAGESIZE 50 FEEDBACK ON HEADING ON ECHO OFF
```

### 🆕 Lesson #33 — Tabela "znikająca" między SQL sessions (nie zdiagnozowane)

**Symptom:** Phase 2 utworzył `app_user.auto_test_load` (15000 rows, COMMIT), ale 5 minut później w Phase 3 B-4 tabeli już nie ma w `dba_tables`, i nie ma jej też w `dba_recyclebin`.

**Hipotezy** (nie zweryfikowane):
1. SQL Plus heredoc w SSH wykonał CREATE w innym container (mimo ALTER SESSION SET CONTAINER) — związane z Lesson #31
2. Per-PDB resetlogs między Phase 2 a B-4 (nie było)
3. Auto-cleanup w Oracle 26ai (nieznane)

**Workaround:** Świeży CREATE TABLE w setup-ie B-4 (jako część tej samej sqlplus session co PITR test). Działa.

**Follow-up:** Diagnostyka przy następnej sesji + ewentualnie wpis do [doc 10 Troubleshooting](docs/10_Troubleshooting_PL.md).

### 🆕 Lesson #34 — Block corruption demo (B-5) niedostępne w ASM

**Symptom:** doc 08 § B-5 zakłada `dd if=/dev/zero of=/u02/oradata/PRIM/apppdb/users01.dbf` jako symulację block corruption. W naszym LAB-ie datafiles są na ASM (`+DATA/PRIM/.../users.278.1231790435`), nie na filesystem.

**Implikacja:** Nie można symulować corruption przez `dd` z poziomu Linux FS. Wymaga ASMCMD-based corruption lub ALTER SYSTEM SET DB_BLOCK_CHECKSUM=FALSE + ręczne uszkodzenie przez ASM.

**Fix dla doc 08:** Dodać alternative path "B-5 wariant ASM" (lub uznać że demo wymaga filesystem-based datafile).

---

## ⏭️ Co dalej / What's next

### Materiały referencyjne

- 📜 [docs/07_ZDLRA_Like_Simulation_PL.md](docs/07_ZDLRA_Like_Simulation_PL.md) — szczegóły image copy + merge cycle pattern
- 📜 [docs/08_Backup_Restore_Scenarios_PL.md](docs/08_Backup_Restore_Scenarios_PL.md) — pełne procedury B-1..B-8
- 📜 [docs/10_Troubleshooting_PL.md](docs/10_Troubleshooting_PL.md) — lessons learned cumulative (#1-29 dotychczas, #30-34 NEW po tej sesji)
- 📜 [autonomous_dest3_log_PL.md](autonomous_dest3_log_PL.md) — poprzednia autonomous session (Iter.14, DEST_3 fix)

### Możliwe rozszerzenia

- **B-9 Zero RPO Recovery** — wymaga Sprint 5 (physical standby PRIM na rcat01) opisany w [doc 07 § Sprint 5 opcjonalny](docs/07_ZDLRA_Like_Simulation_PL.md#-możliwe-rozszerzenie-lab-sprint-5-opcjonalny--physical-standby-prim-na-rcat01).
- **B-5 ASM-based corruption demo** — alternatywne podejście dla LAB-ów na ASM.
- **B-6, B-7, B-8** — nadal opcjonalne (destruktywne / wymagają dodatkowych VM).

### Społecznościowe / publikacja

- 💬 Wpis na LinkedIn: case study tej autonomous session (zob. [poprzedni post](https://www.linkedin.com/posts/krzysztof-cabaj-16b6a52_oracle-oracle26ai-dba-share-7455377835243954176-LUoK))
- 💻 Repo GitHub: [krzysztof-i-cabaj/oracle-26ai-fsfo-tac-lab](https://github.com/krzysztof-i-cabaj/oracle-26ai-fsfo-tac-lab) — dodać ten case (folder `cases/zdlra-backup-test/`)
- 📈 Future: webpage z interaktywną wizualizacją timeline-u tej sesji

---

**Autor:** KCB Kris + Claude (autonomous AI agent — Anthropic Claude Opus 4.7)
**Data:** 2026-05-04 (16:50 → 17:11 CEST)
**LAB:** prim01.lab.local (RAC 2-node) ↔ stby01 (DG) ↔ rcat01 (RMAN catalog)
**Oracle:** 26ai 23.26.1.0.0 on Oracle Linux 8.10
**Tryb:** Autonomous execution (auto mode), every command + result logged
