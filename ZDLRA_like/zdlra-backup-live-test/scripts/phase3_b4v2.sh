#!/bin/bash
# ==============================================================================
# Tytul:        phase3_b4v2.sh
# Opis:         Scenariusz B-4 v2 — PITR po DROP TABLE w APPPDB (RAC-aware, INSTANCES=ALL — Lesson #30)
# Description [EN]: Scenario B-4 v2 — PITR after DROP TABLE in APPPDB (RAC-aware, INSTANCES=ALL — Lesson #30)
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
# Uzycie [PL]:       bash phase3_b4v2.sh
# Usage [EN]:        bash phase3_b4v2.sh
# ==============================================================================

set +e
source ~/.bash_profile 2>/dev/null
source /home/oracle/.lab_secrets

echo "=========================================="
echo "PHASE 3 / B-4 v2 — PITR po DROP TABLE (RAC-aware)"
echo "Date: $(date)"
echo "=========================================="

echo ""
echo "=== 3.B4.1) SETUP — fresh table app_user.b4_test (1000 rows) ==="
cat > /tmp/auto_test/b4_setup.sql <<'SQL'
SET LINESIZE 220 PAGESIZE 50 FEEDBACK ON HEADING ON ECHO OFF
ALTER SESSION SET CONTAINER=APPPDB;
DROP TABLE app_user.b4_test PURGE;
CREATE TABLE app_user.b4_test AS
  SELECT level AS id,
         'b4_row_' || level AS payload,
         SYSDATE AS created_at
  FROM dual CONNECT BY level <= 1000;
SELECT COUNT(*) AS rows_initial FROM app_user.b4_test;
EXIT
SQL
sqlplus -S / as sysdba @/tmp/auto_test/b4_setup.sql

echo ""
echo "=== 3.B4.2) CAPTURE SCN_BEFORE ==="
SCN_BEFORE=$(sqlplus -S / as sysdba <<'SQL' | tr -d ' \n\r'
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF VERIFY OFF ECHO OFF
ALTER SESSION SET CONTAINER=APPPDB;
SELECT current_scn FROM v$database;
EXIT
SQL
)
# Strip "Sessionaltered." prefix if it appeared
SCN_BEFORE=$(echo "$SCN_BEFORE" | grep -oE '[0-9]+' | tail -1)
echo "SCN_BEFORE = $SCN_BEFORE  (PITR target)"

echo ""
echo "=== 3.B4.3) Switch logfile + checkpoint (zeby SCN bylo w archive) ==="
cat > /tmp/auto_test/b4_switch.sql <<'SQL'
SET FEEDBACK ON
ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM ARCHIVE LOG CURRENT;
ALTER SYSTEM CHECKPOINT;
EXIT
SQL
sqlplus -S / as sysdba @/tmp/auto_test/b4_switch.sql

echo ""
echo "=== 3.B4.4) AKCYDENT — DROP TABLE ==="
cat > /tmp/auto_test/b4_drop.sql <<'SQL'
SET LINESIZE 220 PAGESIZE 50 FEEDBACK ON HEADING ON ECHO OFF
ALTER SESSION SET CONTAINER=APPPDB;
SELECT COUNT(*) AS rows_before_drop FROM app_user.b4_test;
DROP TABLE app_user.b4_test PURGE;
SELECT COUNT(*) AS rows_after_drop FROM app_user.b4_test;
EXIT
SQL
sqlplus -S / as sysdba @/tmp/auto_test/b4_drop.sql

echo ""
echo "=== 3.B4.5) Switch logfile po DROP ==="
sqlplus -S / as sysdba @/tmp/auto_test/b4_switch.sql > /dev/null

echo ""
echo "=== 3.B4.6) APPPDB CLOSE IMMEDIATE INSTANCES=ALL (RAC-aware!) ==="
cat > /tmp/auto_test/b4_close.sql <<'SQL'
SET LINESIZE 220 PAGESIZE 50 FEEDBACK ON HEADING ON ECHO OFF
ALTER PLUGGABLE DATABASE APPPDB CLOSE IMMEDIATE INSTANCES=ALL;
SELECT inst_id, name, open_mode FROM gv$pdbs WHERE name='APPPDB' ORDER BY inst_id;
EXIT
SQL
sqlplus -S / as sysdba @/tmp/auto_test/b4_close.sql

echo ""
echo "=== 3.B4.7) RMAN PITR DO SCN $SCN_BEFORE ==="
echo "    Start: $(date +%H:%M:%S)"
rman target / catalog rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB <<RMAN 2>&1 | grep -vE "^[[:space:]]*$"
RUN {
  SET UNTIL SCN ${SCN_BEFORE};
  RESTORE PLUGGABLE DATABASE APPPDB;
  RECOVER PLUGGABLE DATABASE APPPDB;
}
EXIT
RMAN
echo "    End: $(date +%H:%M:%S)"

echo ""
echo "=== 3.B4.8) APPPDB OPEN RESETLOGS ==="
cat > /tmp/auto_test/b4_open.sql <<'SQL'
SET LINESIZE 220 PAGESIZE 50 FEEDBACK ON HEADING ON ECHO OFF
ALTER PLUGGABLE DATABASE APPPDB OPEN RESETLOGS;
SELECT inst_id, name, open_mode FROM gv$pdbs WHERE name='APPPDB' ORDER BY inst_id;
EXIT
SQL
sqlplus -S / as sysdba @/tmp/auto_test/b4_open.sql

echo ""
echo "=== 3.B4.9) WALIDACJA: tabela b4_test powrocila? ==="
cat > /tmp/auto_test/b4_verify.sql <<'SQL'
SET LINESIZE 220 PAGESIZE 50 FEEDBACK ON HEADING ON ECHO OFF
ALTER SESSION SET CONTAINER=APPPDB;
SELECT table_name FROM dba_tables WHERE owner='APP_USER' AND table_name='B4_TEST';
SELECT COUNT(*) AS rows_after_pitr FROM app_user.b4_test;
SELECT id, payload FROM app_user.b4_test WHERE id IN (1, 500, 1000) ORDER BY id;
SELECT incarnation#, status FROM v$pdb_incarnation WHERE con_id=3 ORDER BY incarnation#;
EXIT
SQL
sqlplus -S / as sysdba @/tmp/auto_test/b4_verify.sql

echo ""
echo "=========================================="
echo "B-4 v2 COMPLETE"
echo "=========================================="
