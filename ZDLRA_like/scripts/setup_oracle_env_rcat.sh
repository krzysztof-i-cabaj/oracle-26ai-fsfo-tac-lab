#!/bin/bash
# ==============================================================================
# Tytul:        setup_oracle_env_rcat.sh
# Opis:         Konfiguruje srodowisko Oracle dla uzytkownika oracle na rcat01:
#               .bash_profile (ORACLE_HOME, ORACLE_SID, PATH, LD_LIBRARY_PATH),
#               sysctl/limits jesli kickstart nie zalatwil, /etc/oratab placeholder.
# Description [EN]: Configures oracle env on rcat01 (.bash_profile, oratab, etc.).
#
# Autor:        KCB Kris
# Data:         2026-05-01
# Wersja:       1.0
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - Uruchamiac jako root na rcat01
#                    - Po kickstart (oracle user istnieje, /u01 mounty gotowe)
# Requirements [EN]: - Run as root on rcat01 after kickstart finished.
#
# Uzycie [PL]:  bash setup_oracle_env_rcat.sh
# Usage [EN]:   bash setup_oracle_env_rcat.sh
# ==============================================================================

set -euo pipefail

log() { echo "[$(date +%H:%M:%S)] $*"; }

[ "$(id -u)" -eq 0 ] || { echo "BLAD: Uruchom jako root."; exit 1; }
[ "$(hostname -s)" = "rcat01" ] || { echo "BLAD: Skrypt dla rcat01 (host: $(hostname -s))."; exit 1; }

ORACLE_BASE="/u01/app/oracle"
ORACLE_HOME="$ORACLE_BASE/product/23.26/dbhome_1"
ORACLE_SID="RCAT"

log "=== Konfiguracja srodowiska Oracle dla rcat01 ==="

# 1. .bash_profile dla oracle
BASHPROFILE="/home/oracle/.bash_profile"
if grep -q "ORACLE_HOME=" "$BASHPROFILE" 2>/dev/null; then
    log "[skip] .bash_profile juz zawiera ORACLE_HOME"
else
    log "Dopisuje konfiguracje Oracle do $BASHPROFILE"
    cat >> "$BASHPROFILE" <<EOF

# === Oracle environment for rcat01 (RMAN catalog) ===
export ORACLE_BASE=$ORACLE_BASE
export ORACLE_HOME=$ORACLE_HOME
export ORACLE_SID=$ORACLE_SID
export PATH=\$ORACLE_HOME/bin:\$PATH
export LD_LIBRARY_PATH=\$ORACLE_HOME/lib:\$LD_LIBRARY_PATH
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
export TNS_ADMIN=\$ORACLE_HOME/network/admin
umask 022
EOF
    chown oracle:oinstall "$BASHPROFILE"
    log "[OK] .bash_profile zaktualizowany"
fi

# 2. /etc/oratab placeholder (DBCA dopisze finalna linijke)
# UWAGA: ZAWSZE wymuszamy chown/chmod (nawet jesli plik istnieje od kickstart).
# Konwencja Oracle: oratab ma byc writable dla grupy oinstall, zeby user oracle
# mogl edytowac BEZ sudo (dbca_create_rcat.sh dopisuje flage Y).
# Bez tego: dbca skrypt wisi na 'sudo sed' z timeoutem hasla (incydent 2026-05-03).
# IMPORTANT: ALWAYS enforce chown/chmod (even if file exists from kickstart).
# Oracle convention: oratab writable for oinstall group so oracle user can edit
# WITHOUT sudo. Without this dbca script hangs on 'sudo sed' password timeout.
if [ ! -f /etc/oratab ]; then
    log "Tworze /etc/oratab"
    cat > /etc/oratab <<'EOF'
# /etc/oratab - Format: SID:ORACLE_HOME:auto_start_flag (Y|N)
# DBCA dopisze linijke RCAT po stworzeniu bazy.
EOF
fi
log "Wymuszenie wlascicieli i uprawnien /etc/oratab (Oracle convention: 664 root:oinstall)"
chown root:oinstall /etc/oratab
chmod 664 /etc/oratab

# 3. Walidacja kernel params (kickstart powinno juz to zrobic, ale sanity check)
log "Walidacja kernel params (sysctl)..."
sysctl -p /etc/sysctl.d/99-oracle-hugepages.conf 2>/dev/null || log "[WARN] hugepages config brak - sprawdz kickstart"

# 4. Walidacja mounts
log "Walidacja mounts..."
for mp in /u01 /u02 /u03 /u04 /mnt/rman_bck /mnt/oracle_binaries; do
    if mountpoint -q "$mp" || [ -d "$mp" ]; then
        log "  [OK]   $mp"
    else
        log "  [WARN] $mp - brak mountpoint"
    fi
done

# 5. Walidacja huge pages
# Oczekiwane 512 (=1 GB) - zmniejszone z 1024 (=2 GB) w Iteracji 2 (2026-05-03)
# z powodu memory pressure przy 4 GB RAM (kernel oops + journald watchdog crash).
# Expected 512 (=1 GB) - reduced from 1024 in Iteration 2 due to memory pressure on 4 GB RAM.
HP=$(grep HugePages_Total /proc/meminfo | awk '{print $2}')
log "HugePages_Total: $HP (oczekiwane 512 dla 4 GB RAM, post Iteracja 2 fix)"

log "=== Konfiguracja srodowiska Oracle dla rcat01 zakonczona ==="
log ""
log "Nastepny krok / Next step:"
log "  su - oracle"
log "  bash /tmp/scripts/install_db_silent_rcat.sh /tmp/scripts/db_rcat_se2.rsp"
