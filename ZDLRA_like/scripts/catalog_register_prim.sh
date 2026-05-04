#!/bin/bash
# ==============================================================================
# Tytul:        catalog_register_prim.sh
# Opis:         Rejestruje baze PRIM (RAC) w katalogu RMAN na rcat01.
#               Wywoluje sql/03_register_databases.sql przez SSH na prim01.
# Description [EN]: Registers PRIM database in RMAN catalog via SSH to prim01.
#
# Autor:        KCB Kris
# Data:         2026-05-01
# Wersja:       1.0
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - Uruchamiac NA rcat01 (lub innym hoscie z SSH key do oracle@prim01)
#                    - catalog_create.sh wykonany (schemat + CREATE CATALOG)
#                    - SSH equiv oracle@rcat01 -> oracle@prim01
#                    - PRIM dostepny przez TNS jako 'PRIM' lub bezposredni connection string
# Requirements [EN]: - Run on rcat01, catalog already created, SSH equiv set up.
#
# Uzycie [PL]:  bash catalog_register_prim.sh
# Usage [EN]:   bash catalog_register_prim.sh
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

log() { echo "[$(date +%H:%M:%S)] $*"; }

PRIM_HOST="prim01.lab.local"
PRIM_USER="oracle"
RCAT_HOST="rcat01.lab.local"
RCAT_TNS="rcat01:1521/RCATPDB"
RCAT_USER="rman_cat"
RCAT_PWD="${LAB_PASS}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/../sql/03_register_databases.sql"

[ -f "$SQL_FILE" ] || { echo "BLAD: $SQL_FILE nie istnieje"; exit 1; }

log "=== Rejestracja PRIM w katalogu RMAN ==="

log "1) Test reachability rcat01 z prim01..."
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ${PRIM_USER}@${PRIM_HOST} \
    "tnsping ${RCAT_TNS} 2>&1 | tail -5" || { log "[FAIL] PRIM nie widzi rcat01:1521. Sprawdz siec/listener."; exit 1; }

log "2) Kopiuje SQL na prim01..."
scp -o StrictHostKeyChecking=no "$SQL_FILE" ${PRIM_USER}@${PRIM_HOST}:/tmp/03_register_databases.sql

log "3) Uruchamiam RMAN na prim01: TARGET=/, CATALOG=rcat01..."
# UWAGA: REGISTER DATABASE failuje z RMAN-20002 jesli baza juz zarejestrowana
# (re-run tego skryptu). set +e w SSH-bash zeby walidacja w kroku 4 zdecydowala.
# Lesson 2026-05-03 iter.9: REGISTER nie ma natywnego IF NOT REGISTERED.
# Quoting: connect string w cudzyslowach bo $LAB_PASS moze zawierac '!' (bash history expansion).
set +e
ssh -o StrictHostKeyChecking=no ${PRIM_USER}@${PRIM_HOST} bash <<SSHEOF
set -e
source ~/.bash_profile
rman target / catalog "${RCAT_USER}/${RCAT_PWD}@${RCAT_TNS}" <<RMAN
@/tmp/03_register_databases.sql
RMAN
SSHEOF
RMAN_RC=$?
set -e
if [ $RMAN_RC -ne 0 ]; then
    log "[INFO] RMAN exit $RMAN_RC - moze 'database already registered' (re-run). Walidacja w kroku 4 potwierdzi."
fi

log "4) Walidacja na rcat01: czy PRIM jest w katalogu?"
sqlplus -S ${RCAT_USER}/${RCAT_PWD}@${RCAT_TNS} <<SQLEOF
SET HEADING ON FEEDBACK ON LINESIZE 100
COLUMN db_name FORMAT A20 HEADING "DB Name"
COLUMN db_id FORMAT 9999999999 HEADING "DBID"
SELECT name AS db_name, dbid AS db_id FROM rc_database;
EXIT
SQLEOF

log "=== PRIM zarejestrowany w katalogu RMAN ==="
log ""
log "Test backup (Sprint 2):"
log "  bash rman_full_backup.sh"
