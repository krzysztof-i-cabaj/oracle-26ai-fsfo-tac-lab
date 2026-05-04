#!/bin/bash
# ==============================================================================
# Tytul:        rman_full_backup.sh
# Opis:         FULL DATABASE BACKUP (Level 0) z PRIM + ARCHIVELOG + autobackup
#               controlfile. Skladowane w /mnt/rman_bck/full/. Rejestrowane w
#               katalogu na rcat01.
# Description [EN]: Full DB Level 0 backup of PRIM + archivelog + cf autobackup.
#                   Stored in /mnt/rman_bck/full/, registered in catalog on rcat01.
#
# Autor:        KCB Kris
# Data:         2026-05-01
# Wersja:       1.0
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - Uruchamiac NA prim01 jako oracle
#                    - Katalog dziala (catalog_register_prim.sh wykonany)
#                    - /mnt/rman_bck zamontowany na PRIM (vboxsf)
#                    - 10_rman_config_persistent.sql wykonany (retention/compression)
# Requirements [EN]: - Run on prim01 as oracle, catalog ready, /mnt/rman_bck mounted.
#
# Uzycie [PL]:  bash rman_full_backup.sh
# Usage [EN]:   bash rman_full_backup.sh
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
TAG="weekly_l0_$(date +%Y%m%d)"

[ "$USER" = "oracle" ] || { echo "BLAD: Uruchom jako oracle."; exit 1; }
[ -d "/mnt/rman_bck" ] || { echo "BLAD: /mnt/rman_bck nie zamontowany."; exit 1; }

# Tworz subkatalogi jesli brak
mkdir -p /mnt/rman_bck/{full,arch,cf}

log "=========================================================="
log "  RMAN FULL BACKUP (Level 0) - PRIM"
log "  TAG: $TAG"
log "=========================================================="

rman target / catalog "$CATALOG_TNS" <<RMAN
RUN {
    # 4 kanaly rownolegle (zgodnie z CONFIGURE PARALLELISM 4)
    ALLOCATE CHANNEL c1 DEVICE TYPE DISK FORMAT '/mnt/rman_bck/full/db_%d_%T_%U';
    ALLOCATE CHANNEL c2 DEVICE TYPE DISK FORMAT '/mnt/rman_bck/full/db_%d_%T_%U';
    ALLOCATE CHANNEL c3 DEVICE TYPE DISK FORMAT '/mnt/rman_bck/full/db_%d_%T_%U';
    ALLOCATE CHANNEL c4 DEVICE TYPE DISK FORMAT '/mnt/rman_bck/full/db_%d_%T_%U';

    # FULL backup (level 0)
    BACKUP
      INCREMENTAL LEVEL 0
      AS COMPRESSED BACKUPSET
      TAG '$TAG'
      DATABASE
      PLUS ARCHIVELOG
        FORMAT '/mnt/rman_bck/arch/arc_%d_%T_%U'
        DELETE INPUT;

    RELEASE CHANNEL c1;
    RELEASE CHANNEL c2;
    RELEASE CHANNEL c3;
    RELEASE CHANNEL c4;
}

# Sprawdz status
LIST BACKUP SUMMARY COMPLETED AFTER 'SYSDATE-1/24';
EXIT
RMAN

log "=========================================================="
log "  FULL BACKUP zakonczony ($TAG)"
log "  Lokalizacja: /mnt/rman_bck/full/"
log "=========================================================="

# Po-backup raport: rozmiar
log "Rozmiar /mnt/rman_bck/:"
du -sh /mnt/rman_bck/* 2>/dev/null
