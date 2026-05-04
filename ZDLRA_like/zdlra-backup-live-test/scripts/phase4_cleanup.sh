#!/bin/bash
# ==============================================================================
# Tytul:        phase4_cleanup.sh
# Opis:         Phase 4 — Post-test cleanup + DG verification + final state report
# Description [EN]: Phase 4 — Post-test cleanup + DG verification + final state report
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
# Uzycie [PL]:       bash phase4_cleanup.sh
# Usage [EN]:        bash phase4_cleanup.sh
# ==============================================================================

set +e
source ~/.bash_profile 2>/dev/null
source /home/oracle/.lab_secrets

echo "=========================================="
echo "PHASE 4 - Post-test cleanup + DG verify"
echo "Date: $(date)"
echo "=========================================="

echo ""
echo "=== 4.1) Open APPPDB on PRIM2 (after RESETLOGS only PRIM1 was open) ==="
cat > /tmp/auto_test/p4_open.sql <<'SQL'
SET LINESIZE 220 PAGESIZE 50 FEEDBACK ON HEADING ON ECHO OFF
ALTER PLUGGABLE DATABASE APPPDB OPEN INSTANCES=ALL;
SELECT inst_id, name, open_mode FROM gv$pdbs WHERE name='APPPDB' ORDER BY inst_id;
EXIT
SQL
sqlplus -S / as sysdba @/tmp/auto_test/p4_open.sql

echo ""
echo "=== 4.2) Cleanup test table app_user.b4_test ==="
cat > /tmp/auto_test/p4_drop.sql <<'SQL'
SET LINESIZE 220 FEEDBACK ON ECHO OFF
ALTER SESSION SET CONTAINER=APPPDB;
DROP TABLE app_user.b4_test PURGE;
SELECT 'b4_test cleanup OK' AS status FROM dual;
EXIT
SQL
sqlplus -S / as sysdba @/tmp/auto_test/p4_drop.sql

echo ""
echo "=== 4.3) DG broker SHOW CONFIGURATION (po PITR APPPDB) ==="
dgmgrl -silent / "SHOW CONFIGURATION;"

echo ""
echo "=== 4.4) DG SHOW DATABASE VERBOSE STBY ==="
dgmgrl -silent / "SHOW DATABASE STBY;" 2>&1 | head -40

echo ""
echo "=== 4.5) Apply lag na STBY (transport + apply) ==="
cat > /tmp/auto_test/p4_lag.sql <<'SQL'
SET LINESIZE 220 PAGESIZE 50 FEEDBACK ON HEADING ON ECHO OFF
SELECT name, value FROM v$dataguard_stats WHERE name IN ('transport lag', 'apply lag', 'apply finish time', 'estimated startup time');
EXIT
SQL
sqlplus -S sys/${LAB_PASS}@stby01:1521/STBY as sysdba @/tmp/auto_test/p4_lag.sql 2>&1 | tail -15

echo ""
echo "=== 4.6) Final RMAN catalog state — backup count summary ==="
cat > /tmp/auto_test/p4_count.sql <<'SQL'
SET LINESIZE 220 PAGESIZE 50 FEEDBACK ON HEADING ON ECHO OFF
SELECT bp.tag, COUNT(*) AS pieces, ROUND(SUM(bp.bytes)/1024/1024,1) AS total_mb
FROM rc_backup_piece bp WHERE bp.start_time > SYSDATE - 1
GROUP BY bp.tag ORDER BY 1;
EXIT
SQL
sqlplus -S rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB @/tmp/auto_test/p4_count.sql

echo ""
echo "=== 4.7) Final filesystem state ==="
echo "incr_merge:"
du -sh /mnt/rman_bck/incr_merge/
echo "full:"
du -sh /mnt/rman_bck/full/
echo "arch:"
du -sh /mnt/rman_bck/arch/
echo "cf:"
du -sh /mnt/rman_bck/cf/
echo ""
echo "Disk free:"
df -h /mnt/rman_bck

echo ""
echo "=========================================="
echo "PHASE 4 COMPLETE — Auto test session done"
echo "=========================================="
