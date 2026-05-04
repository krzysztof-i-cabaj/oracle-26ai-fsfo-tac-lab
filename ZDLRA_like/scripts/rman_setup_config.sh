#!/bin/bash
# ==============================================================================
# Tytul:        rman_setup_config.sh
# Opis:         Persistent RMAN configuration dla bazy PRIM (jednorazowy setup
#               polityki backupowej Sprint 2). Wywoluje sql/10_rman_config_persistent.sql
#               przez RMAN z TARGET=PRIM, CATALOG=rcat01. Walidacja przez SHOW ALL.
# Description [EN]: Persistent RMAN configuration for PRIM (one-off Sprint 2 backup
#                   policy setup). Calls sql/10_rman_config_persistent.sql via RMAN
#                   with TARGET=PRIM, CATALOG=rcat01. Validation via SHOW ALL.
#
# Autor:        KCB Kris
# Data:         2026-05-04
# Wersja:       1.0
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - Uruchamiac NA prim01 jako oracle (analog do rman_full_backup.sh)
#                    - PRIM zarejestrowany w katalogu (catalog_register_prim.sh wykonany)
#                    - rcat01:1521/RCATPDB osiagalne (TNS lub HOSTNAME adapter)
#                    - /mnt/rman_bck zamontowany (vboxsf - dla CONFIGURE FORMAT cf_*/bp_*)
# Requirements [EN]: - Run on prim01 as oracle, PRIM registered in catalog, rcat01 reachable,
#                      /mnt/rman_bck mounted.
#
# Uzycie [PL]:  bash rman_setup_config.sh
# Usage [EN]:   bash rman_setup_config.sh
#
# Idempotencja [PL]: CONFIGURE jest idempotentne - re-run nadpisuje wartosci bez bledu.
# Idempotency [EN]:  CONFIGURE is idempotent - re-run overwrites without error.
# ==============================================================================

set -euo pipefail

# --- LAB secrets (konwencja VMs2-install) ---
[ -r /root/.lab_secrets ] && source /root/.lab_secrets
[ -r "$HOME/.lab_secrets" ] && source "$HOME/.lab_secrets"
if [ -z "${LAB_PASS:-}" ]; then
    echo "BLAD: LAB_PASS nieustawiona. Stworz /root/.lab_secrets z 'export LAB_PASS=...' (chmod 600)."
    echo "ERROR: LAB_PASS not set. Create /root/.lab_secrets with 'export LAB_PASS=...' (chmod 600)."
    exit 1
fi

log() { echo "[$(date +%Y-%m-%d\ %H:%M:%S)] $*"; }

CATALOG_TNS="rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/../sql/10_rman_config_persistent.sql"

# --- Pre-checks ---
[ "$USER" = "oracle" ] || { echo "BLAD: Uruchom jako oracle (analog do innych rman_*.sh). / ERROR: Run as oracle."; exit 1; }
[ -f "$SQL_FILE" ] || { echo "BLAD: $SQL_FILE nie istnieje. Sprawdz strukture projektu."; exit 1; }
[ -d "/mnt/rman_bck" ] || { echo "OSTRZEZENIE: /mnt/rman_bck nie zamontowany. CONFIGURE FORMAT bedzie zapisany ale backupy potem failuja."; }

log "=========================================================="
log "  Persistent RMAN config setup (Sprint 2 - jednorazowy)   "
log "  Persistent RMAN config setup (Sprint 2 - one-off)       "
log "=========================================================="

# Tworz subkatalogi cf/full/incr/arch jesli /mnt/rman_bck zamontowany
if [ -d "/mnt/rman_bck" ]; then
    mkdir -p /mnt/rman_bck/{cf,full,incr,arch} 2>/dev/null || true
    log "Subkatalogi /mnt/rman_bck/{cf,full,incr,arch} gotowe."
fi

# --- Krok 1: Wykonaj CONFIGURE ze sql/10 ---
log "1) Uruchamiam RMAN: TARGET=/, CATALOG=rcat01, @sql/10_rman_config_persistent.sql..."
# Quoting: connect string w cudzyslowach bo $LAB_PASS moze zawierac '!' (bash history expansion).
rman target / catalog "${CATALOG_TNS}" <<RMANEOF
@${SQL_FILE}
RMANEOF

# --- Krok 2: Walidacja - osobne polaczenie, czyste SHOW ALL ---
log ""
log "2) Walidacja - SHOW ALL (oczekiwane: 9 CONFIGURE settings):"
rman target / catalog "${CATALOG_TNS}" <<RMANEOF
SHOW RETENTION POLICY;
SHOW BACKUP OPTIMIZATION;
SHOW CONTROLFILE AUTOBACKUP;
SHOW CONTROLFILE AUTOBACKUP FORMAT;
SHOW DEVICE TYPE;
SHOW COMPRESSION ALGORITHM;
SHOW CHANNEL;
SHOW ARCHIVELOG DELETION POLICY;
SHOW SNAPSHOT CONTROLFILE NAME;
EXIT
RMANEOF

log ""
log "=========================================================="
log "  Persistent RMAN config = DONE                            "
log "=========================================================="
log ""
log "Nastepne kroki / Next steps:"
log "  - Test backup ad-hoc:  bash rman_full_backup.sh"
log "  - Cron deployment:     patrz docs/06_Backup_Policy_PL.md sekcja 'Cron'"
