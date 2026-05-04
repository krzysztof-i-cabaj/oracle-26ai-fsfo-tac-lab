#!/bin/bash
# ==============================================================================
# Tytul:        zdlra_sim_setup.sh
# Opis:         ZDLRA-like simulation setup. Konfiguruje:
#               1. Real-time redo transport PRIM -> rcat01 (LOG_ARCHIVE_DEST_3)
#               2. Incremental merge cycle (Virtual Full Backup pattern)
# Description [EN]: ZDLRA-like simulation: real-time redo + virtual full backup.
#
# Autor:        KCB Kris
# Data:         2026-05-04 (v1.3: DB_UNIQUE_NAME=RCAT zamiast rcat_redo, lesson #28)
#               (v1.2: + ALTER LOG_ARCHIVE_CONFIG przed DEST_3, lesson #26)
#               (v1.1: # zamiast -- w heredoc RMAN, lesson #20 retroactively)
# Wersja:       1.3
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - PRIM, rcat01 dzialaja, katalog skonfigurowany
#                    - Listener na rcat01 zarejestrowal serwis 'rcat01_redo'
#                    - tnsnames na PRIM: rcat01_redo zdefiniowane
# Requirements [EN]: - PRIM, rcat01 up, catalog ready, TNS rcat01_redo defined
#
# Uzycie [PL]:  bash zdlra_sim_setup.sh --init        # initial L0 image copy + config
#               bash zdlra_sim_setup.sh --merge       # daily merge (cron)
#               bash zdlra_sim_setup.sh --status      # status incremental merge cycle
# Usage [EN]:   --init | --merge | --status
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
INCR_MERGE_TAG="incr_merge"
INCR_MERGE_DEST="/mnt/rman_bck/incr_merge"

ACTION=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --init)   ACTION="init";   shift ;;
        --merge)  ACTION="merge";  shift ;;
        --status) ACTION="status"; shift ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

[ -n "$ACTION" ] || { echo "Uzycie: --init | --merge | --status"; exit 1; }
[ "$USER" = "oracle" ] || { echo "BLAD: Uruchom jako oracle."; exit 1; }

mkdir -p "$INCR_MERGE_DEST"

case "$ACTION" in
init)
    log "============================================="
    log "  ZDLRA-LIKE INIT (one-time setup)"
    log "============================================="

    # 1) Real-time redo transport PRIM -> rcat01 (db_unique_name=RCAT)
    # Lesson #26 (iter.14): RCAT MUSI byc w DG_CONFIG, inaczej ORA-16053
    # 'DB_UNIQUE_NAME ... is not in the Data Guard Configuration'.
    # Lesson #28 (iter.14): DB_UNIQUE_NAME w DEST_3 musi byc faktycznym db_unique_name bazy
    # docelowej (RCAT na rcat01), NIE aliasem TNS service-u (rcat_redo) - inaczej ORA-16191
    # 'log shipping client unable to log onto target database' bo Oracle weryfikuje match
    # przy login.
    log "1a) Dodaje RCAT do LOG_ARCHIVE_CONFIG (DG_CONFIG)..."
    sqlplus -S / as sysdba <<'SQL'
ALTER SYSTEM SET LOG_ARCHIVE_CONFIG='DG_CONFIG=(PRIM,STBY,RCAT)' SCOPE=BOTH;
SHOW PARAMETER log_archive_config;
EXIT
SQL

    log "1b) Konfiguracja LOG_ARCHIVE_DEST_3 na PRIM (real-time redo do RCAT)..."
    log "    (TNS alias RCAT01_REDO mapuje na rcat01:1521/rcat_redo, ale DB_UNIQUE_NAME=RCAT)"
    sqlplus -S / as sysdba <<'SQL'
ALTER SYSTEM SET LOG_ARCHIVE_DEST_3=
  'SERVICE=RCAT01_REDO ASYNC NOAFFIRM
   VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE)
   DB_UNIQUE_NAME=RCAT' SCOPE=BOTH;
ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_3=ENABLE SCOPE=BOTH;
ALTER SYSTEM SWITCH LOGFILE;
SELECT dest_id, dest_name, status, error FROM v$archive_dest WHERE dest_id IN (1,2,3);
EXIT
SQL

    # 2) Initial Level 0 IMAGE COPY (nie backupset!)
    log "2) Initial Level 0 IMAGE COPY do $INCR_MERGE_DEST..."
    rman target / catalog "$CATALOG_TNS" <<RMAN
RUN {
    ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
    ALLOCATE CHANNEL c2 DEVICE TYPE DISK;

    BACKUP
      INCREMENTAL LEVEL 0
      AS COPY
      TAG '$INCR_MERGE_TAG'
      DATABASE
      FORMAT '$INCR_MERGE_DEST/df_%d_%U';

    RELEASE CHANNEL c1;
    RELEASE CHANNEL c2;
}
LIST COPY OF DATABASE TAG '$INCR_MERGE_TAG';
EXIT
RMAN

    log "============================================="
    log "  INIT zakonczony. Ustaw cron --merge co 24h."
    log "  Cron: 0 3 * * * /tmp/scripts/zdlra_sim_setup.sh --merge"
    log "============================================="
    ;;

merge)
    log "============================================="
    log "  ZDLRA-LIKE DAILY MERGE (incremental + recover image copy)"
    log "============================================="

    rman target / catalog "$CATALOG_TNS" <<RMAN
RUN {
    ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
    ALLOCATE CHANNEL c2 DEVICE TYPE DISK;

    # KROK 1: Aplikuj poprzedni incremental L1 do image copy (jesli istnieje)
    # Po pierwszym dniu nic do mergowania, drugi dzien juz tak.
    RECOVER COPY OF DATABASE WITH TAG '$INCR_MERGE_TAG';

    # KROK 2: Nowy incremental L1 dla merge na nastepny dzien
    BACKUP
      INCREMENTAL LEVEL 1
      FOR RECOVER OF COPY WITH TAG '$INCR_MERGE_TAG'
      DATABASE
      FORMAT '$INCR_MERGE_DEST/incr_%d_%U';

    RELEASE CHANNEL c1;
    RELEASE CHANNEL c2;
}

# Po merge: image copy jest "jak swiezy L0"
LIST COPY OF DATABASE TAG '$INCR_MERGE_TAG';
EXIT
RMAN

    log "MERGE done. Image copy aktualny - jak swiezy Level 0 bez kosztu pelnego L0."
    ;;

status)
    log "============================================="
    log "  ZDLRA-LIKE STATUS"
    log "============================================="

    log "1) LOG_ARCHIVE_DEST_3 status:"
    sqlplus -S / as sysdba <<'SQL'
SET LINESIZE 200
COLUMN dest_name FORMAT A20
COLUMN target FORMAT A30
COLUMN status FORMAT A12
COLUMN error FORMAT A30
SELECT dest_id, dest_name, target, status, error FROM v$archive_dest WHERE dest_id=3;
EXIT
SQL

    log "2) Image copy + incremental status:"
    rman target / catalog "$CATALOG_TNS" <<RMAN
LIST COPY OF DATABASE TAG '$INCR_MERGE_TAG';
LIST BACKUP OF DATABASE TAG '$INCR_MERGE_TAG';
EXIT
RMAN

    log "3) Rozmiar /mnt/rman_bck/incr_merge:"
    du -sh "$INCR_MERGE_DEST"
    ;;
esac
