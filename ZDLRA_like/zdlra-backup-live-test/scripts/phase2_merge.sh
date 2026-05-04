#!/bin/bash
# ==============================================================================
# Tytul:        phase2_merge.sh
# Opis:         Phase 2 — Backup merge cycle: workload simulation + new L1 INCR FOR RECOVER OF COPY + archivelog backup
# Description [EN]: Phase 2 — Backup merge cycle: workload simulation + new L1 INCR FOR RECOVER OF COPY + archivelog backup
#
# Autor:        KCB Kris + Claude (autonomous AI agent — Anthropic Claude Opus 4.7)
# Data:         2026-05-04
# Wersja:       1.0
# <repo>:       ZDLRA_like/zdlra-backup-live-test
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - Oracle 26ai 23.26.1.0.0 on Oracle Linux 8.10 (RAC 2-node + DG + RMAN catalog)
#                    - Skrypt uruchamiany na prim01 jako oracle
#                    - source /home/oracle/.lab_secrets (eksport LAB_PASS)
#                    - SSH passwordless mesh do rcat01
# Requirements [EN]: - Oracle 26ai 23.26.1.0.0 on Oracle Linux 8.10 (2-node RAC + DG + RMAN catalog)
#                    - Run on prim01 as oracle user
#                    - source /home/oracle/.lab_secrets (exports LAB_PASS)
#                    - SSH passwordless mesh to rcat01
#
# Uzycie [PL]:       bash phase2_merge.sh
# Usage [EN]:        bash phase2_merge.sh
# ==============================================================================

set +e
source ~/.bash_profile 2>/dev/null
source /home/oracle/.lab_secrets

echo "=========================================="
echo "PHASE 2 — Backup merge cycle"
echo "Date: $(date)"
echo "=========================================="

echo ""
echo "=== 2.1) Symulacja workload — DML w APPPDB.APP_USER ==="
sqlplus -S / as sysdba <<'SQL'
SET LINESIZE 200
ALTER SESSION SET CONTAINER=APPPDB;

PROMPT --- BEFORE: SCN + APP_USER objects ---
SELECT current_scn FROM v$database;
SELECT object_type, COUNT(*) FROM dba_objects WHERE owner='APP_USER' GROUP BY object_type;

PROMPT --- Tworzymy testową tabelę + insert 10000 rows ---
CREATE TABLE APP_USER.auto_test_load AS
SELECT level AS id,
       'workload_row_' || level AS payload,
       SYSDATE AS created_at,
       SYS_GUID() AS row_guid
FROM dual CONNECT BY level <= 10000;

PROMPT --- Update massive ---
UPDATE APP_USER.auto_test_load SET payload = payload || '_updated' WHERE MOD(id, 3) = 0;
COMMIT;

PROMPT --- Insert another 5000 ---
INSERT INTO APP_USER.auto_test_load (id, payload, created_at, row_guid)
SELECT 10000 + level, 'second_batch_' || level, SYSDATE, SYS_GUID()
FROM dual CONNECT BY level <= 5000;
COMMIT;

PROMPT --- AFTER: row count + SCN ---
SELECT COUNT(*) AS auto_test_load_rows FROM APP_USER.auto_test_load;
SELECT current_scn FROM v$database;
EXIT
SQL

echo ""
echo "=== 2.2) Wymuszenie archivelog switches ==="
sqlplus -S / as sysdba <<'SQL'
SET LINESIZE 200
PROMPT --- Switch logfile x 4 ---
ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM SWITCH LOGFILE;
PROMPT --- Last 5 archived logs ---
COL name FORMAT a90
SELECT sequence#, thread#, name, status FROM v$archived_log
WHERE first_time > SYSDATE - 1/24
ORDER BY first_time DESC FETCH FIRST 5 ROWS ONLY;
EXIT
SQL

echo ""
echo "=== 2.3) BACKUP INCREMENTAL LEVEL 1 FOR RECOVER OF COPY (new L1) ==="
echo "    Start: $(date +%H:%M:%S)"
rman target / catalog rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB <<'RMAN' 2>&1 | tail -100
RUN {
  BACKUP INCREMENTAL LEVEL 1 FOR RECOVER OF COPY
    WITH TAG 'incr_merge'
    DATABASE
    FORMAT '/mnt/rman_bck/incr_merge/incr_%d_%U';
}
EXIT
RMAN
echo "    End: $(date +%H:%M:%S)"

echo ""
echo "=== 2.4) BACKUP ARCHIVELOG ALL (nieskopiowane) ==="
echo "    Start: $(date +%H:%M:%S)"
rman target / catalog rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB <<'RMAN' 2>&1 | tail -40
BACKUP ARCHIVELOG ALL NOT BACKED UP 1 TIMES TAG 'auto_test_arch'
  FORMAT '/mnt/rman_bck/arch/arc_%d_%T_%U';
EXIT
RMAN
echo "    End: $(date +%H:%M:%S)"

echo ""
echo "=== 2.5) STATUS po Phase 2 ==="
rman target / catalog rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB <<'RMAN' 2>&1 | tail -80
LIST COPY OF DATABASE TAG 'incr_merge';
LIST BACKUP OF DATABASE TAG 'incr_merge';
REPORT SCHEMA;
EXIT
RMAN

echo ""
echo "=== 2.6) Filesystem state ==="
ls -lah /mnt/rman_bck/incr_merge/ | head -25
echo ""
echo "Total incr_merge:"
du -sh /mnt/rman_bck/incr_merge/
echo "Total full:"
du -sh /mnt/rman_bck/full/
echo "Total arch:"
du -sh /mnt/rman_bck/arch/

echo ""
echo "=========================================="
echo "PHASE 2 COMPLETE"
echo "=========================================="
