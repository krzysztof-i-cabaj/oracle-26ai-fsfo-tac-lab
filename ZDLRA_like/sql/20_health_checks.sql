-- ==============================================================================
-- Tytul:        20_health_checks.sql
-- Opis:         Zapytania diagnostyczne katalogu RMAN i statusu backupow.
--               Uruchamiac jako rman_cat w PDB RCATPDB lub jako sysdba na PRIM.
-- Description [EN]: Health-check queries for RMAN catalog + backup status.
--
-- Autor:        KCB Kris
-- Data:         2026-05-01
-- Wersja:       1.0
-- <repo>:       ZDLRA_like
-- Konwencje:    ZDLRA_like/SETTINGS.md
--
-- Uzycie [PL]:  sqlplus rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB @20_health_checks.sql
-- Usage [EN]:   Same.
-- ==============================================================================

SET LINESIZE 220
SET PAGESIZE 100
SET FEEDBACK ON

PROMPT ============================================================
PROMPT  HEALTH CHECK 1: Zarejestrowane bazy w katalogu
PROMPT  HEALTH CHECK 1: Registered databases in catalog
PROMPT ============================================================

COLUMN db_name FORMAT A20 HEADING "DB Name"
COLUMN dbid FORMAT 99999999999 HEADING "DBID"
COLUMN reset_scn FORMAT 99999999999 HEADING "Reset SCN"
COLUMN reset_time FORMAT A20 HEADING "Reset Time"
SELECT name AS db_name, dbid, reset_scn, TO_CHAR(reset_time,'YYYY-MM-DD HH24:MI') AS reset_time
  FROM rc_database
  ORDER BY dbid;

PROMPT
PROMPT ============================================================
PROMPT  HEALTH CHECK 2: Ostatnie backupy (Top 20 najnowszych)
PROMPT  HEALTH CHECK 2: Latest backups (Top 20)
PROMPT ============================================================

COLUMN db_name FORMAT A12 HEADING "DB"
COLUMN backup_type FORMAT A4 HEADING "Type"
COLUMN start_time FORMAT A18 HEADING "Started"
COLUMN end_time FORMAT A18 HEADING "Finished"
COLUMN size_mb FORMAT 999999 HEADING "Size_MB"
COLUMN tag FORMAT A20 HEADING "Tag"
SELECT * FROM (
    SELECT bs.db_name,
           bs.backup_type,
           TO_CHAR(bs.start_time,'YYYY-MM-DD HH24:MI') AS start_time,
           TO_CHAR(bs.completion_time,'YYYY-MM-DD HH24:MI') AS end_time,
           ROUND(bs.bytes/1024/1024) AS size_mb,
           bs.tag
      FROM rc_backup_set bs
     ORDER BY bs.completion_time DESC
) WHERE ROWNUM <= 20;

PROMPT
PROMPT ============================================================
PROMPT  HEALTH CHECK 3: Sumaryczny rozmiar backupow per typ
PROMPT  HEALTH CHECK 3: Total backup size by type
PROMPT ============================================================

COLUMN backup_type FORMAT A12 HEADING "Backup Type"
COLUMN cnt FORMAT 999999 HEADING "Count"
COLUMN total_gb FORMAT 999999.99 HEADING "Total_GB"
SELECT db_name,
       DECODE(backup_type,'D','DATAFILE FULL/INCR','I','INCREMENTAL','L','ARCHIVELOG',backup_type) AS backup_type,
       COUNT(*) AS cnt,
       ROUND(SUM(bytes)/1024/1024/1024, 2) AS total_gb
  FROM rc_backup_set
  GROUP BY db_name, backup_type
  ORDER BY db_name, backup_type;

PROMPT
PROMPT ============================================================
PROMPT  HEALTH CHECK 4: Backupy NIESKONCZONE (running > 1h)
PROMPT  HEALTH CHECK 4: Stuck backup jobs (running > 1h)
PROMPT ============================================================

COLUMN sid FORMAT 99999 HEADING "SID"
COLUMN start_time FORMAT A18 HEADING "Started"
COLUMN elapsed FORMAT A12 HEADING "Elapsed"
SELECT bs.db_name,
       TO_CHAR(bs.start_time,'YYYY-MM-DD HH24:MI') AS start_time,
       TO_CHAR(SYSDATE - bs.start_time, '999990.99') AS elapsed
  FROM rc_backup_set bs
 WHERE bs.completion_time IS NULL
   AND bs.start_time < SYSDATE - 1/24
 ORDER BY bs.start_time;

PROMPT
PROMPT ============================================================
PROMPT  HEALTH CHECK 5: ARCHIVELOG gap (PRIM nie zbackupowany od X dni)
PROMPT  HEALTH CHECK 5: Archivelog gap (not backed up for X days)
PROMPT ============================================================

COLUMN db_name FORMAT A12
COLUMN last_arch_backup FORMAT A20 HEADING "Last_Arch_Backup"
COLUMN gap_days FORMAT 999.99 HEADING "Gap_Days"
SELECT db.name AS db_name,
       TO_CHAR(MAX(bs.completion_time),'YYYY-MM-DD HH24:MI') AS last_arch_backup,
       SYSDATE - MAX(bs.completion_time) AS gap_days
  FROM rc_database db, rc_backup_set bs
 WHERE bs.db_id = db.dbid
   AND bs.backup_type = 'L'
 GROUP BY db.name
 ORDER BY gap_days DESC;

PROMPT
PROMPT ============================================================
PROMPT  HEALTH CHECK 6: Sukces ratio backupow z ostatnich 7 dni
PROMPT  HEALTH CHECK 6: Backup success ratio last 7 days
PROMPT ============================================================

SELECT db_name,
       COUNT(*) AS total_jobs,
       COUNT(CASE WHEN completion_time IS NOT NULL THEN 1 END) AS successful,
       ROUND(100 * COUNT(CASE WHEN completion_time IS NOT NULL THEN 1 END) / COUNT(*), 1) AS success_pct
  FROM rc_backup_set
 WHERE start_time > SYSDATE - 7
 GROUP BY db_name
 ORDER BY db_name;

EXIT
