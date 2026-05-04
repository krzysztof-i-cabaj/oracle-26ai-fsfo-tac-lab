#!/bin/bash
# ==============================================================================
# Tytul:        phase3_b1.sh
# Opis:         Scenariusz B-1 — Pelny cykl katalogu RMAN (REGISTER -> FULL -> CROSSCHECK -> LIST)
# Description [EN]: Scenario B-1 — Full RMAN catalog cycle (REGISTER -> FULL -> CROSSCHECK -> LIST)
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
# Uzycie [PL]:       bash phase3_b1.sh
# Usage [EN]:        bash phase3_b1.sh
# ==============================================================================

set +e
source ~/.bash_profile 2>/dev/null
source /home/oracle/.lab_secrets

echo "=========================================="
echo "PHASE 3 / B-1 — Pelny cykl katalogu RMAN"
echo "Date: $(date)"
echo "=========================================="

echo ""
echo "=== 3.B1.1) Status katalogu (PRIM + STBY zarejestrowane?) ==="
sqlplus -S rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB <<'SQL'
SET LINESIZE 200
SET PAGESIZE 50
SET FEEDBACK OFF
COL name FORMAT a8
COL db_unique_name FORMAT a14
COL database_role FORMAT a18
SELECT d.name, d.dbid, s.db_unique_name, s.database_role
FROM rc_database d JOIN rc_site s ON d.db_key=s.db_key
ORDER BY s.db_unique_name;
EXIT
SQL

echo ""
echo "=== 3.B1.2) FULL BACKUP COMPRESSED (database + archivelog) ==="
echo "    Start: $(date +%H:%M:%S)"
rman target / catalog rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB <<'RMAN' 2>&1 | grep -E "^(channel|allocated|backup|piece|input|Starting|Finished|RMAN|disconnect|reconnection|Compressed|input archived|Tag)" | head -80
BACKUP INCREMENTAL LEVEL 0 AS COMPRESSED BACKUPSET TAG 'auto_test_b1' DATABASE PLUS ARCHIVELOG;
EXIT
RMAN
echo "    End: $(date +%H:%M:%S)"

echo ""
echo "=== 3.B1.3) CROSSCHECK + DELETE EXPIRED ==="
rman target / catalog rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB <<'RMAN' 2>&1 | grep -E "^(crosschecked|RMAN-|deleted|Crosschecked|specification|List of|backup piece|allocated|channel|RMAN|finished)" | head -60
CROSSCHECK BACKUP;
CROSSCHECK ARCHIVELOG ALL;
DELETE NOPROMPT EXPIRED BACKUP;
DELETE NOPROMPT EXPIRED ARCHIVELOG ALL;
EXIT
RMAN

echo ""
echo "=== 3.B1.4) LIST BACKUP SUMMARY (po B-1) ==="
rman target / catalog rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB <<'RMAN' 2>&1 | grep -E "^(BS Key|[0-9]+|List of|RMAN)" | head -30
LIST BACKUP SUMMARY;
EXIT
RMAN

echo ""
echo "=== 3.B1.5) RC_BACKUP_PIECE summary (catalog side) ==="
sqlplus -S rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB <<'SQL'
SET LINESIZE 200
SET PAGESIZE 50
SET FEEDBACK OFF
COL backup_type FORMAT a8
COL piece_type FORMAT a10
COL status FORMAT a8
COL tag FORMAT a16

PROMPT --- Pieces with tag auto_test_b1 ---
SELECT bp.bs_key, bp.piece#, bp.bytes/1024/1024 AS mb, bp.status, bs.backup_type, bp.tag
FROM rc_backup_piece bp
JOIN rc_backup_set bs ON bp.bs_key = bs.bs_key
WHERE bp.tag = 'AUTO_TEST_B1'
ORDER BY bp.bs_key, bp.piece#;

PROMPT --- All backup pieces summary by tag (today) ---
SELECT bp.tag, COUNT(*) AS pieces, ROUND(SUM(bp.bytes)/1024/1024) AS total_mb
FROM rc_backup_piece bp
WHERE bp.start_time > SYSDATE - 1
GROUP BY bp.tag
ORDER BY bp.tag;
EXIT
SQL

echo ""
echo "=========================================="
echo "B-1 COMPLETE"
echo "=========================================="
