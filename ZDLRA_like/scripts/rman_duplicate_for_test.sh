#!/bin/bash
# ==============================================================================
# Tytul:        rman_duplicate_for_test.sh
# Opis:         DUPLICATE DATABASE FROM BACKUPSET - tworzy kopie testowa PRIM
#               na innej maszynie (np. client01 lub osobny VM). Realny use-case
#               DBA: refresh srodowiska TEST z PROD.
# Description [EN]: DUPLICATE DATABASE FROM BACKUPSET to create test env from PRIM.
#
# Autor:        KCB Kris
# Data:         2026-05-01
# Wersja:       1.0
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# UWAGA [PL]: Ten skrypt sluzy jako TEMPLATE. Wymaga wczesniej:
#   - przygotowania docelowej VM (auxiliary instance) z pustym ORACLE_HOME
#   - tnsnames z wpisem AUX (auxiliary)
#   - auxiliary instance startup NOMOUNT
# NOTE [EN]: This is a TEMPLATE. Requires aux VM with empty ORACLE_HOME, TNS, NOMOUNT.
#
# Uzycie [PL]:  bash rman_duplicate_for_test.sh --aux <AUX_TNS> --target_db <name>
# Usage [EN]:   See above.
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

AUX_TNS=""
TARGET_DB="PRIM"
NEW_DB_NAME="TEST"
while [[ $# -gt 0 ]]; do
    case "$1" in
        #aux)        AUX_TNS="$2";    shift 2 ;;
        #target_db)  TARGET_DB="$2";  shift 2 ;;
        #new_name)   NEW_DB_NAME="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

[ -n "$AUX_TNS" ] || { echo "Uzycie: --aux <AUX_TNS> [--target_db PRIM] [--new_name TEST]"; exit 1; }
[ "$USER" = "oracle" ] || { echo "BLAD: Uruchom jako oracle."; exit 1; }

log "=========================================================="
log "  RMAN DUPLICATE: TARGET=$TARGET_DB -> AUX=$AUX_TNS"
log "  New DB name: $NEW_DB_NAME"
log "=========================================================="
log ""
log "Pre-reqs (zrob to recznie przed wywolaniem skryptu):"
log "  1. Aux VM ma pusty \$ORACLE_HOME zainstalowany"
log "  2. /etc/oratab ma wpis: $NEW_DB_NAME:..."
log "  3. tnsnames.ora na PRIM ma wpis $AUX_TNS"
log "  4. AUX startup NOMOUNT z dummy initfile"
log ""
read -r -p "Pre-reqs spelnione? Kontynuowac? (yes/no): " confirm
[ "$confirm" = "yes" ] || { log "Anulowano."; exit 0; }

rman target / auxiliary sys/${LAB_PASS}@${AUX_TNS} catalog "$CATALOG_TNS" <<RMAN
RUN {
    DUPLICATE TARGET DATABASE TO $NEW_DB_NAME
        FROM ACTIVE DATABASE
        SPFILE
            SET db_name='$NEW_DB_NAME'
            SET db_unique_name='$NEW_DB_NAME'
            SET control_files='/u02/oradata/$NEW_DB_NAME/control01.ctl'
            SET log_archive_dest_2=''
            SET log_archive_dest_3=''
            SET fal_server=''
            SET fal_client=''
        NOFILENAMECHECK;
}
EXIT
RMAN

log "=========================================================="
log "  DUPLICATE zakonczony. Nowy DB '$NEW_DB_NAME' otwarty."
log "  Walidacja:"
log "    sqlplus sys/...@$AUX_TNS as sysdba"
log "    SQL> SELECT name, db_unique_name FROM v\$database;"
log "=========================================================="
