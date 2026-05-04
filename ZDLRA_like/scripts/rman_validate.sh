#!/bin/bash
# ==============================================================================
# Tytul:        rman_validate.sh
# Opis:         RESTORE DATABASE VALIDATE (i archivelog) - sprawdza czy backupy
#               sa poprawne i mozliwe do uzycia BEZ realnego restore.
#               Krytyczne dla SLA "backup nie jest backupem dopoki nie zostal zwalidowany".
# Description [EN]: RESTORE VALIDATE on backups (DB + archivelog) without actual restore.
#                   "A backup is not a backup until it's been validated."
#
# Autor:        KCB Kris
# Data:         2026-05-01
# Wersja:       1.0
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Uzycie [PL]:  Na prim01 jako oracle: bash rman_validate.sh
# Usage [EN]:   On prim01 as oracle.
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

[ "$USER" = "oracle" ] || { echo "BLAD: Uruchom jako oracle."; exit 1; }

log "=== RMAN BACKUP VALIDATE ==="

rman target / catalog "$CATALOG_TNS" <<'RMAN'
# Walidacja struktury backupow (rozkodowanie naglowkow, sprawdzenie checksum)
RESTORE DATABASE VALIDATE;
RESTORE ARCHIVELOG ALL VALIDATE;
RESTORE CONTROLFILE VALIDATE;

# Walidacja blok-po-bloku (wolniejsze, ale dokladne)
# VALIDATE BACKUPSET <set_id> CHECK LOGICAL;

# Walidacja samej bazy (sprawdz blok corruption w datafilach)
VALIDATE DATABASE;

# Sprawdz czy mamy KOMPLETNY recovery path
RESTORE DATABASE PREVIEW SUMMARY;

EXIT
RMAN

log "=== VALIDATE done ==="
log "Sprawdz output: szukaj 'failed' lub 'corrupt'. Jesli czysto - backupy OK."
