#!/bin/bash
# ==============================================================================
# Tytul:        phase1_zdlra_init.sh
# Opis:         Phase 1 — ZDLRA-Like full backup (RECOVER COPY OF DATABASE — forward-progress image copy)
# Description [EN]: Phase 1 — ZDLRA-Like full backup (RECOVER COPY OF DATABASE — forward-progress image copy)
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
# Uzycie [PL]:       bash phase1_zdlra_init.sh
# Usage [EN]:        bash phase1_zdlra_init.sh
# ==============================================================================

set +e
source ~/.bash_profile 2>/dev/null
source /home/oracle/.lab_secrets

echo "=========================================="
echo "PHASE 1 — ZDLRA-Like full backup"
echo "Pattern: image copy + RECOVER COPY (apply prev L1)"
echo "Date: $(date)"
echo "=========================================="

echo ""
echo "=== 1.1) STATUS przed Phase 1 — image copy + L1 incrementals ==="
rman target / catalog rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB <<'RMAN' 2>&1
LIST COPY OF DATABASE TAG 'incr_merge';
LIST BACKUP OF DATABASE TAG 'incr_merge';
EXIT
RMAN

echo ""
echo "=== 1.2) Pre-merge: bieżący SCN bazy ==="
sqlplus -S / as sysdba <<'SQL'
SET LINESIZE 200
SELECT current_scn, to_char(SYSDATE,'YYYY-MM-DD HH24:MI:SS') AS now FROM v$database;
EXIT
SQL

echo ""
echo "=== 1.3) RECOVER COPY OF DATABASE WITH TAG 'incr_merge' ==="
echo "    (apply previously taken L1 incrementals to advance the image copy)"
echo "    Start time: $(date +%H:%M:%S)"
rman target / catalog rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB <<'RMAN' 2>&1
RECOVER COPY OF DATABASE WITH TAG 'incr_merge';
EXIT
RMAN
echo "    End time: $(date +%H:%M:%S)"

echo ""
echo "=== 1.4) STATUS po RECOVER COPY ==="
rman target / catalog rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB <<'RMAN' 2>&1
LIST COPY OF DATABASE TAG 'incr_merge';
EXIT
RMAN

echo ""
echo "=== 1.5) Filesystem state (/mnt/rman_bck/incr_merge/) ==="
ls -lah /mnt/rman_bck/incr_merge/ | head -25
echo "Total size:"
du -sh /mnt/rman_bck/incr_merge/

echo ""
echo "=========================================="
echo "PHASE 1 COMPLETE"
echo "=========================================="
