#!/bin/bash
# ==============================================================================
# Tytul:        rman_incremental_l1.sh
# Opis:         Incremental Level 1 CUMULATIVE backup z PRIM + ARCHIVELOG.
#               Codzienne backupowanie zmian od ostatniego Level 0.
# Description [EN]: Incremental L1 cumulative backup of PRIM + archivelog. Daily.
#
# Autor:        KCB Kris
# Data:         2026-05-01
# Wersja:       1.0
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - Uruchamiac na prim01 jako oracle
#                    - Wczesniej musi byc Level 0 (rman_full_backup.sh)
# Requirements [EN]: - Run on prim01 as oracle, after Level 0 exists.
#
# Uzycie [PL]:  bash rman_incremental_l1.sh
# Usage [EN]:   bash rman_incremental_l1.sh
# ==============================================================================

set -euo pipefail

# --- LAB secrets (konwencja VMs2-install) ---
# Source haslo zunifikowane LAB z /root/.lab_secrets (lub $HOME/.lab_secrets).
# Plik tworzony przez kickstart (ks-rcat01.cfg) z chmod 600.
[ -r /root/.lab_secrets ] && source /root/.lab_secrets
[ -r "$HOME/.lab_secrets" ] && source "$HOME/.lab_secrets"
if [ -z "${LAB_PASS:-}" ]; then
    echo "BLAD: LAB_PASS nieustawiona. Stworz /root/.lab_secrets z 'export LAB_PASS=...' (chmod 600)."
    echo "ERROR: LAB_PASS not set. Create /root/.lab_secrets with 'export LAB_PASS=...' (chmod 600)."
    exit 1
fi

log() { echo "[$(date +%Y-%m-%d\ %H:%M:%S)] $*"; }

CATALOG_TNS="rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB"
TAG="daily_l1_$(date +%Y%m%d)"

[ "$USER" = "oracle" ] || { echo "BLAD: Uruchom jako oracle."; exit 1; }
[ -d "/mnt/rman_bck" ] || { echo "BLAD: /mnt/rman_bck nie zamontowany."; exit 1; }

mkdir -p /mnt/rman_bck/incr

log "=========================================================="
log "  RMAN INCREMENTAL L1 CUMULATIVE BACKUP - PRIM"
log "  TAG: $TAG"
log "=========================================================="

rman target / catalog "$CATALOG_TNS" <<RMAN
RUN {
    ALLOCATE CHANNEL c1 DEVICE TYPE DISK FORMAT '/mnt/rman_bck/incr/db_%d_%T_%U';
    ALLOCATE CHANNEL c2 DEVICE TYPE DISK FORMAT '/mnt/rman_bck/incr/db_%d_%T_%U';

    BACKUP
      INCREMENTAL LEVEL 1 CUMULATIVE
      AS COMPRESSED BACKUPSET
      TAG '$TAG'
      DATABASE
      PLUS ARCHIVELOG
        FORMAT '/mnt/rman_bck/arch/arc_%d_%T_%U'
        DELETE INPUT;

    RELEASE CHANNEL c1;
    RELEASE CHANNEL c2;
}

LIST BACKUP SUMMARY COMPLETED AFTER 'SYSDATE-1/24';
EXIT
RMAN

log "=========================================================="
log "  INCREMENTAL L1 zakonczony ($TAG)"
log "=========================================================="
