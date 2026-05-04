#!/bin/bash
# ==============================================================================
# Tytul:        rman_archivelog_only.sh
# Opis:         Backup samych archivelogow z PRIM. Dla cron co 15 min - daje RPO < 15 min.
#               Z opcja DELETE INPUT po sukcesie (zwalnia FRA na PRIM).
# Description [EN]: Archivelog-only backup of PRIM. Run via cron every 15 min for RPO<15.
#
# Autor:        KCB Kris
# Data:         2026-05-04 (v1.2: + echo log path + set +u dla source bash_profile)
#               (v1.1: LOG_FILE w $HOME zamiast /var/log/)
# Wersja:       1.2
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - Uruchamiac na prim01 jako oracle (cron oracle)
#                    - Cron entry: */15 * * * * /tmp/scripts/rman_archivelog_only.sh
# Requirements [EN]: - Run on prim01 as oracle (cron). Entry: every 15 min.
#
# Uzycie [PL]:  bash rman_archivelog_only.sh
# Usage [EN]:   bash rman_archivelog_only.sh
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

# Logging do pliku - default w $HOME/rman_logs/ (lokalnie pisalny przez oracle).
# Dla cron deployment z central log /var/log/rman_arch_*.log: setup raz przez root:
#   sudo touch /var/log/rman_arch.log && sudo chown oracle:oinstall /var/log/rman_arch.log
# Potem override w cron entry: LOG_DIR=/var/log */15 * * * * /tmp/scripts/rman_archivelog_only.sh
# Lesson iter.12: oryginal v1.0 zakladal /var/log/ ale oracle nie ma write tam by default.
LOG_DIR="${LOG_DIR:-${HOME}/rman_logs}"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/rman_arch_$(date +%Y%m%d).log"

# Dla manual run: poinformuj usera gdzie poleci log (bo exec redirect zara wszystko ukryje).
# For manual run: tell user where the log goes (exec redirect below hides everything).
echo "[$(date +%H:%M:%S)] Logging do / Logging to: $LOG_FILE"
echo "[$(date +%H:%M:%S)] Tail w innym terminalu / Tail in another terminal: tail -f $LOG_FILE"
echo ""

exec >> "$LOG_FILE" 2>&1

log() { echo "[$(date +%Y-%m-%d\ %H:%M:%S)] $*"; }

CATALOG_TNS="rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB"
TAG="arch_$(date +%Y%m%d_%H%M)"

# Source bash_profile (cron nie ma env). UWAGA: bash_profile moze miec unset variables
# ktore wywalaja set -u. Tymczasowo wylaczamy set -u dla source.
# Lesson iter.12: bez set +u/set -u wokol source skrypt tu wywala bez sladu w log file
# (errror trafia na stderr ktory juz przekierowany do log file ale process exit przed flush).
set +u
source /home/oracle/.bash_profile 2>/dev/null || true
set -u

[ -d "/mnt/rman_bck" ] || { log "BLAD: /mnt/rman_bck nie zamontowany"; exit 1; }
mkdir -p /mnt/rman_bck/arch

log "=== ARCHIVELOG BACKUP TAG=$TAG ==="

rman target / catalog "$CATALOG_TNS" <<RMAN
RUN {
    ALLOCATE CHANNEL c1 DEVICE TYPE DISK FORMAT '/mnt/rman_bck/arch/arc_%d_%T_%U';

    # Backup wszystkich nie-zbackupowanych archivelogs
    BACKUP
      AS COMPRESSED BACKUPSET
      TAG '$TAG'
      ARCHIVELOG ALL
      NOT BACKED UP 1 TIMES
      DELETE ALL INPUT;

    RELEASE CHANNEL c1;
}
EXIT
RMAN

log "=== ARCHIVELOG BACKUP done ==="
