#!/bin/bash
# ==============================================================================
# Tytul:        rman_restore_controlfile.sh
# Opis:         Disaster recovery: utrata controlfile + spfile.
#               Restore z autobackup (CONFIGURE CONTROLFILE AUTOBACKUP ON musi byc).
# Description [EN]: DR scenario: lost controlfile + spfile. Restore from autobackup.
#
# Autor:        KCB Kris
# Data:         2026-05-01
# Wersja:       1.0
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - Plik autobackup w /mnt/rman_bck/cf/cf_*
#                    - Baza PRIM padla (instance down)
#                    - DBID PRIM znany (z poprzednich logow lub LIST DB_UNIQUE_NAME)
# Requirements [EN]: - Autobackup file present, instance down, DBID known.
#
# Uzycie [PL]:  bash rman_restore_controlfile.sh --dbid <DBID>
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
DBID=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        #dbid) DBID="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

[ -n "$DBID" ] || { echo "Uzycie: --dbid <DBID>"; echo "Znajdz DBID: rman target / catalog ... <<< 'LIST DB_UNIQUE_NAME ALL;'"; exit 1; }
[ "$USER" = "oracle" ] || { echo "BLAD: Uruchom jako oracle."; exit 1; }

log "=========================================================="
log "  DISASTER RECOVERY: Controlfile/spfile restore"
log "  DBID=$DBID"
log "=========================================================="

# 1) Zamknij baze (jesli czesciowo dziala)
log "1) Shutdown abort (jesli dziala)..."
sqlplus / as sysdba <<'SQL' || true
SHUTDOWN ABORT;
EXIT
SQL

# 2) Startup NOMOUNT bez spfile
log "2) Startup NOMOUNT z dummy init..."
cat > /tmp/init_dummy.ora <<'INIT'
db_name='PRIM'
db_unique_name='PRIM'
INIT

sqlplus / as sysdba <<SQL || true
STARTUP NOMOUNT PFILE='/tmp/init_dummy.ora';
EXIT
SQL

# 3) Restore spfile + controlfile z autobackup
log "3) RMAN: SET DBID + RESTORE SPFILE + CONTROLFILE..."
rman target / catalog "$CATALOG_TNS" <<RMAN
SET DBID $DBID;

# Restore spfile z autobackup
RESTORE SPFILE FROM AUTOBACKUP;

# Restart z restored spfile
SHUTDOWN IMMEDIATE;
STARTUP NOMOUNT;

# Restore controlfile
RESTORE CONTROLFILE FROM AUTOBACKUP;

# Mount + recover (do najnowszego stanu)
ALTER DATABASE MOUNT;
RECOVER DATABASE;

ALTER DATABASE OPEN RESETLOGS;
EXIT
RMAN

log "=========================================================="
log "  Recovery zakonczony. Baza otwarta z RESETLOGS."
log "  ZALECENIE: zrob FULL backup teraz (nowa incarnation)."
log "=========================================================="
