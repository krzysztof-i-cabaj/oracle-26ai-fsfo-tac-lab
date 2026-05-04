#!/bin/bash
# ==============================================================================
# Tytul:        rman_crosscheck.sh
# Opis:         CROSSCHECK + DELETE EXPIRED + DELETE OBSOLETE.
#               Czysci katalog z plikow ktore zostaly usuniete z dysku
#               i z backupow ktore wygasly wedlug retention policy.
#               Cron: weekly.
# Description [EN]: Crosscheck + cleanup expired/obsolete backups. Run weekly via cron.
#
# Autor:        KCB Kris
# Data:         2026-05-01
# Wersja:       1.0
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Uzycie [PL]:  Na prim01 jako oracle (cron weekly).
# Usage [EN]:   Run on prim01 as oracle (cron weekly).
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

log "=== RMAN CROSSCHECK + CLEANUP ==="

rman target / catalog "$CATALOG_TNS" <<'RMAN'
# 1) CROSSCHECK: znajdz pliki w katalogu ktorych juz nie ma na dysku
CROSSCHECK BACKUP;
CROSSCHECK ARCHIVELOG ALL;
CROSSCHECK COPY;

# 2) DELETE EXPIRED: usun z katalogu metadane plikow ktore zniknely z dysku
DELETE NOPROMPT EXPIRED BACKUP;
DELETE NOPROMPT EXPIRED ARCHIVELOG ALL;
DELETE NOPROMPT EXPIRED COPY;

# 3) DELETE OBSOLETE: usun backupy starsze niz retention policy (RECOVERY WINDOW 14 DAYS)
DELETE NOPROMPT OBSOLETE;

# Raport po cleanup
LIST BACKUP SUMMARY;
REPORT OBSOLETE;

EXIT
RMAN

log "=== CROSSCHECK + CLEANUP done ==="

log "Stan /mnt/rman_bck po cleanup:"
du -sh /mnt/rman_bck/* 2>/dev/null
