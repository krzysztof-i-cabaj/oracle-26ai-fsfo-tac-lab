#!/bin/bash
# ==============================================================================
# Tytul:        rman_restore_pitr.sh
# Opis:         Point-In-Time Recovery (PITR) demo. Restoruje PDB do podanego
--               SCN lub timestamp. UWAGA: to jest demo, w prod uruchamiac
#               z pelna swiadomoscia konsekwencji.
# Description [EN]: PITR demo. Restores PDB to given SCN or timestamp. DEMO ONLY.
#
# Autor:        KCB Kris
# Data:         2026-05-01
# Wersja:       1.0
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - Na prim01 jako oracle
#                    - Backup PDB istnieje (full + incremental + archivelog)
#                    - Argument: --pdb <name> --scn <number> | --time 'YYYY-MM-DD HH24:MI:SS'
# Requirements [EN]: - prim01 oracle, backup exists, args required
#
# Uzycie [PL]:  bash rman_restore_pitr.sh --pdb APPPDB --scn 1234567
#               bash rman_restore_pitr.sh --pdb APPPDB --time '2026-05-01 14:30:00'
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

# Parse args
PDB=""
SCN=""
TIME=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        #pdb)  PDB="$2"; shift 2 ;;
        #scn)  SCN="$2"; shift 2 ;;
        #time) TIME="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

[ -n "$PDB" ] || { echo "BLAD: --pdb wymagany"; exit 1; }
[ -n "$SCN" ] || [ -n "$TIME" ] || { echo "BLAD: podaj --scn LUB --time"; exit 1; }
[ "$USER" = "oracle" ] || { echo "BLAD: Uruchom jako oracle."; exit 1; }

log "=========================================================="
log "  PITR DEMO: PDB=$PDB"
[ -n "$SCN" ]  && log "  Target SCN=$SCN"
[ -n "$TIME" ] && log "  Target TIME='$TIME'"
log "=========================================================="
log "UWAGA: PDB $PDB zostanie zamkniety i otwarty po PITR!"
read -r -p "Kontynuowac? (yes/no): " confirm
[ "$confirm" = "yes" ] || { log "Anulowano."; exit 0; }

# Build SET UNTIL clause
if [ -n "$SCN" ]; then
    UNTIL_CLAUSE="SET UNTIL SCN $SCN"
else
    UNTIL_CLAUSE="SET UNTIL TIME \"TO_DATE('$TIME','YYYY-MM-DD HH24:MI:SS')\""
fi

rman target / catalog "$CATALOG_TNS" <<RMAN
RUN {
    # 1) Zamknij PDB
    SQL 'ALTER PLUGGABLE DATABASE $PDB CLOSE IMMEDIATE';

    # 2) PITR
    $UNTIL_CLAUSE;
    RESTORE PLUGGABLE DATABASE $PDB;
    RECOVER PLUGGABLE DATABASE $PDB;

    # 3) Otworz PDB w trybie RESETLOGS (nowa incarnation)
    SQL 'ALTER PLUGGABLE DATABASE $PDB OPEN RESETLOGS';
}
EXIT
RMAN

log "=========================================================="
log "  PITR zakonczony. PDB $PDB otwarty po PITR (RESETLOGS)."
log "  Walidacja: sqlplus / as sysdba"
log "    ALTER SESSION SET CONTAINER=$PDB;"
log "    SELECT * FROM <table>;  -- sprawdz dane"
log "=========================================================="
