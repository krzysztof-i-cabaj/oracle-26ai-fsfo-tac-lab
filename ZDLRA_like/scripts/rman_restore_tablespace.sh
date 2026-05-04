#!/bin/bash
# ==============================================================================
# Tytul:        rman_restore_tablespace.sh
# Opis:         Online tablespace recovery. Restoruje pojedynczy tablespace
#               BEZ zatrzymywania bazy ani PDB. Granular - inne tablespaces dziala dalej.
# Description [EN]: Online tablespace recovery. DB stays open, only TS is restored.
#
# Autor:        KCB Kris
# Data:         2026-05-01
# Wersja:       1.0
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Uzycie [PL]:  bash rman_restore_tablespace.sh --pdb APPPDB --ts USERS
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

PDB=""
TS=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        #pdb) PDB="$2"; shift 2 ;;
        #ts)  TS="$2";  shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

[ -n "$PDB" ] && [ -n "$TS" ] || { echo "Uzycie: --pdb <PDB> --ts <TABLESPACE>"; exit 1; }
[ "$USER" = "oracle" ] || { echo "BLAD: Uruchom jako oracle."; exit 1; }

log "=== Online Tablespace Recovery: PDB=$PDB TS=$TS ==="

rman target / catalog "$CATALOG_TNS" <<RMAN
RUN {
    # 1) Off-line tylko tego tablespace (PDB i inne TS dzialaja dalej)
    SQL 'ALTER PLUGGABLE DATABASE $PDB SAVE STATE';
    ALTER SESSION SET CONTAINER=$PDB;
    SQL 'ALTER TABLESPACE $TS OFFLINE IMMEDIATE';

    # 2) Restore + recover tylko tego tablespace
    RESTORE TABLESPACE $TS;
    RECOVER TABLESPACE $TS;

    # 3) Online z powrotem
    SQL 'ALTER TABLESPACE $TS ONLINE';
}
EXIT
RMAN

log "=== Tablespace $TS w PDB $PDB online ==="
