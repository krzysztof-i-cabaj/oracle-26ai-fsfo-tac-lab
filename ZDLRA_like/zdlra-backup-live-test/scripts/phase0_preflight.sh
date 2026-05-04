#!/bin/bash
# ==============================================================================
# Tytul:        phase0_preflight.sh
# Opis:         Phase 0 — Pre-flight diagnostics (DG, RMAN catalog, storage, APPPDB)
# Description [EN]: Phase 0 — Pre-flight diagnostics (DG, RMAN catalog, storage, APPPDB)
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
# Uzycie [PL]:       bash phase0_preflight.sh
# Usage [EN]:        bash phase0_preflight.sh
# ==============================================================================

set +e
source ~/.bash_profile 2>/dev/null

echo "=========================================="
echo "PHASE 0 — PRE-FLIGHT (run on $(hostname))"
echo "Date: $(date)"
echo "=========================================="

echo ""
echo "=== 1) DB instance status ==="
sqlplus -S / as sysdba <<'SQL'
SET LINESIZE 200
SET PAGESIZE 100
COL host_name FORMAT a20
COL name FORMAT a10
COL open_mode FORMAT a15
COL database_role FORMAT a18
COL db_unique_name FORMAT a16
SELECT name, open_mode, database_role, db_unique_name FROM v$database;
SELECT instance_name, host_name, status FROM v$instance;
SELECT con_id, name, open_mode FROM v$pdbs ORDER BY con_id;
EXIT
SQL

echo ""
echo "=== 2) DG broker SHOW CONFIGURATION ==="
dgmgrl -silent / "SHOW CONFIGURATION;" 2>&1

echo ""
echo "=== 3) v\$archive_dest (DEST_2 + DEST_3) ==="
sqlplus -S / as sysdba <<'SQL'
SET LINESIZE 220
COL destination FORMAT a35
COL status FORMAT a10
COL target FORMAT a12
COL error FORMAT a55
SELECT dest_id, status, target, destination, SUBSTR(error,1,55) AS error FROM v$archive_dest WHERE dest_id IN (1,2,3);
EXIT
SQL

echo ""
echo "=== 4) RMAN catalog connection (rman_cat@rcat01:1521/RCATPDB) ==="
LAB_PASS=$(sudo cat /root/.lab_secrets 2>/dev/null | grep LAB_PASS | cut -d= -f2 | tr -d '"')
if [ -z "$LAB_PASS" ]; then
    echo "ERROR: LAB_PASS not readable"
else
    echo "LAB_PASS: read OK"
fi

sqlplus -S rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB <<'SQL'
SET LINESIZE 200
COL name FORMAT a10
COL db_unique_name FORMAT a18
COL database_role FORMAT a18
SELECT d.name, d.dbid, s.db_unique_name, s.database_role
FROM rc_database d JOIN rc_site s ON d.db_key=s.db_key
ORDER BY s.db_unique_name;
EXIT
SQL

echo ""
echo "=== 5) /mnt/rman_bck struktura ==="
ls -la /mnt/rman_bck/ 2>&1 | head -20
echo ""
echo "--- /mnt/rman_bck/incr_merge/ ---"
ls -la /mnt/rman_bck/incr_merge/ 2>&1 | head -20
echo ""
echo "--- /mnt/rman_bck/full/ ---"
ls -la /mnt/rman_bck/full/ 2>&1 | head -10
echo ""
echo "--- /mnt/rman_bck/arch/ (last 5) ---"
ls -lat /mnt/rman_bck/arch/ 2>&1 | head -8

echo ""
echo "=== 6) Disk space /mnt/rman_bck ==="
df -h /mnt/rman_bck

echo ""
echo "=== 7) APPPDB content + current_scn ==="
sqlplus -S / as sysdba <<'SQL'
SET LINESIZE 200
ALTER SESSION SET CONTAINER=APPPDB;
SELECT current_scn FROM v$database;
SELECT owner, COUNT(*) AS object_count
FROM dba_objects
WHERE owner NOT IN ('SYS','SYSTEM','DBSNMP','PDBADMIN','XDB','GSMADMIN_INTERNAL',
                    'OUTLN','AUDSYS','OJVMSYS','LBACSYS','APPQOSSYS','DVSYS','DVF',
                    'GGSYS','REMOTE_SCHEDULER_AGENT','SYSBACKUP','SYSDG','SYSKM',
                    'SYSRAC','OLAPSYS','MDSYS','MDDATA','CTXSYS','ANONYMOUS','DIP',
                    'ORDDATA','ORDPLUGINS','ORDSYS','SI_INFORMTN_SCHEMA','WMSYS')
GROUP BY owner ORDER BY 1;
EXIT
SQL

echo ""
echo "=== 8) RMAN persistent configuration ==="
rman target / catalog rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB <<'RMAN' 2>&1 | tail -50
SHOW ALL;
EXIT
RMAN

echo ""
echo "=========================================="
echo "PHASE 0 COMPLETE"
echo "=========================================="
