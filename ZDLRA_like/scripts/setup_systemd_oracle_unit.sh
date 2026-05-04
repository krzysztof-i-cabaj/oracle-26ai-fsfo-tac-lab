#!/bin/bash
# ==============================================================================
# Tytul:        setup_systemd_oracle_unit.sh
# Opis:         Instaluje oracle-rcat.service do systemd na rcat01.
#               Po reboocie OS baza RCAT + listener startuja automatycznie.
# Description [EN]: Installs oracle-rcat.service into systemd on rcat01.
#                   DB + listener auto-start after OS reboot.
#
# Autor:        KCB Kris
# Data:         2026-05-01
# Wersja:       1.0
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - Uruchamiac jako root na rcat01
#                    - DB RCAT istnieje (po dbca_create_rcat.sh)
#                    - /etc/oratab zawiera RCAT:...:Y
#                    - Plik ./systemd/oracle-rcat.service obok skryptu
# Requirements [EN]: - root, DB RCAT exists, /etc/oratab Y flag, unit file alongside
#
# Uzycie [PL]:  bash setup_systemd_oracle_unit.sh
# Usage [EN]:   bash setup_systemd_oracle_unit.sh
# ==============================================================================

set -euo pipefail

log() { echo "[$(date +%H:%M:%S)] $*"; }

[ "$(id -u)" -eq 0 ] || { echo "BLAD: Uruchom jako root."; exit 1; }
[ "$(hostname -s)" = "rcat01" ] || { echo "BLAD: Skrypt dla rcat01."; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_SRC="$SCRIPT_DIR/systemd/oracle-rcat.service"
UNIT_DST="/etc/systemd/system/oracle-rcat.service"

[ -f "$UNIT_SRC" ] || { echo "BLAD: Brak $UNIT_SRC"; exit 1; }

log "=== Instalacja systemd unit oracle-rcat.service ==="

# 1) Sanity check: /etc/oratab zawiera RCAT z flaga Y
if ! grep -qE "^RCAT:.*:Y" /etc/oratab; then
    log "[WARN] /etc/oratab NIE zawiera 'RCAT:...:Y' - dbstart NIE wystartuje bazy."
    log "       Sprawdz: cat /etc/oratab. Powinno byc: RCAT:/u01/app/oracle/product/23.26/dbhome_1:Y"
fi

# 2) Skopiuj unit
log "Kopiuje unit -> $UNIT_DST"
cp "$UNIT_SRC" "$UNIT_DST"
chown root:root "$UNIT_DST"
chmod 644 "$UNIT_DST"

# 3) Reload systemd + enable + start
log "systemctl daemon-reload"
systemctl daemon-reload

log "systemctl enable oracle-rcat.service"
systemctl enable oracle-rcat.service

log "systemctl start oracle-rcat.service"
systemctl start oracle-rcat.service || log "[WARN] start zwrocil blad - sprawdz journalctl -u oracle-rcat"

# 4) Walidacja
sleep 5
log "Status:"
systemctl status oracle-rcat.service --no-pager || true

log ""
log "Walidacja: czy listener i DB faktycznie dzialaja?"
su - oracle -c "lsnrctl status 2>&1 | grep -E 'STATUS|Service'" || log "[WARN] lsnrctl status fail"
su - oracle -c "echo 'SELECT status FROM v\$instance;' | sqlplus -S / as sysdba" || log "[WARN] sqlplus fail"

log "=== systemd unit oracle-rcat zainstalowany ==="
log ""
log "Test: reboot rcat01 i sprawdz czy baza wstaje automatycznie."
log "  sudo systemctl reboot"
log "  # po ~120 s:"
log "  systemctl status oracle-rcat   # powinno byc 'active (exited)'"
