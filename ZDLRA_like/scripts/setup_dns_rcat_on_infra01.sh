#!/bin/bash
# ==============================================================================
# Tytul:        setup_dns_rcat_on_infra01.sh
# Opis:         Dodaje wpis DNS dla rcat01 (192.168.56.16) do strefy lab.local
#               na infra01. Idempotentny - sprawdza czy wpis juz istnieje.
#               Uruchamiac NA infra01 jako root.
# Description [EN]: Adds DNS A/PTR record for rcat01 to lab.local zone on infra01.
#                   Idempotent. Run AS root ON infra01.
#
# Autor:        KCB Kris
# Data:         2026-05-01
# Wersja:       1.0
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - BIND/named uruchomiony na infra01
#                    - Strefa lab.local skonfigurowana (przez setup_dns_infra01.sh z VMs2-install)
#                    - Skrypt uruchomiony na infra01 jako root
# Requirements [EN]: - BIND running on infra01, lab.local zone configured, run as root
#
# Uzycie [PL]:  scp setup_dns_rcat_on_infra01.sh root@infra01:/tmp/
#               ssh root@infra01 'bash /tmp/setup_dns_rcat_on_infra01.sh'
# Usage [EN]:   See above (scp + ssh root execution).
# ==============================================================================

set -euo pipefail

RCAT_HOST="rcat01"
RCAT_FQDN="rcat01.lab.local"
RCAT_IP="192.168.56.16"
RCAT_PTR_OCTET="16"

# UWAGA: Sciezki zgodne z VMs2-install/scripts/setup_dns_infra01.sh (linia 76, 82).
# Konwencja BIND: db.<zone> (RHEL/OL default), nie <zone>.zone.
# Lesson learned 2026-05-03: skrypt zakladal 'lab.local.zone' - blad, wlasciwe to 'db.lab.local'.
# NOTE: Paths match VMs2-install/scripts/setup_dns_infra01.sh convention. RHEL/OL default
# is db.<zone>, not <zone>.zone. Fixed 2026-05-03 (script assumed wrong path, FAIL).
ZONE_FORWARD="/var/named/db.lab.local"
ZONE_REVERSE="/var/named/db.56.168.192"

log() { echo "[$(date +%H:%M:%S)] $*"; }

if [ "$(id -u)" -ne 0 ]; then
    echo "BLAD: Uruchom jako root."
    exit 1
fi

if [ "$(hostname -s)" != "infra01" ]; then
    echo "BLAD: Skrypt nalezy uruchomic na infra01 (host: $(hostname -s))."
    exit 1
fi

# Sanity: czy zone files istnieja (zapobiega cichemu fail)
if [ ! -f "$ZONE_FORWARD" ]; then
    echo "BLAD: Forward zone file nie istnieje: $ZONE_FORWARD"
    echo "Sprawdz: ls -la /var/named/ | grep -E 'lab|56.168'"
    exit 1
fi
if [ ! -f "$ZONE_REVERSE" ]; then
    echo "BLAD: Reverse zone file nie istnieje: $ZONE_REVERSE"
    echo "Sprawdz: ls -la /var/named/ | grep -E '56.168'"
    exit 1
fi

log "=== Dodawanie wpisu DNS dla $RCAT_FQDN ($RCAT_IP) ==="

# Helper: bump SOA serial (YYYYMMDDNN) w pliku zone.
# Format BIND z setup_dns_infra01.sh: serial jest na 2-giej linii bloku SOA,
# poprzedzony znakami SOA-paren (), bez komentarza '; serial'.
# Przyklad: "                    2026042801 3600 900 1209600 3600 )"
# Helper: bump SOA serial in zone file. Format from setup_dns_infra01.sh:
# serial on line 2 of SOA block, no '; serial' comment (RHEL/OL default).
bump_serial() {
    local zone_file="$1"
    # Znajdz pierwszy 10-cyfrowy numer zaraz po linii zawierajacej "SOA"
    local cur_serial=$(awk '/SOA/{found=1; next} found && /[0-9]{10}/{match($0,/[0-9]{10}/); print substr($0,RSTART,10); exit}' "$zone_file")
    if [ -z "$cur_serial" ]; then
        echo "BLAD: Nie moge znalezc SOA serial w $zone_file"
        return 1
    fi
    local new_serial=$((cur_serial + 1))
    # Zamien tylko PIERWSZE wystapienie po SOA (-z czyta caly plik jako jeden record dla awk-style scope)
    sed -i "0,/${cur_serial}/{s/${cur_serial}/${new_serial}/}" "$zone_file"
    echo "$cur_serial -> $new_serial"
}

# 1) Forward zone
if grep -q "^${RCAT_HOST}[[:space:]]" "$ZONE_FORWARD"; then
    log "[skip] Wpis $RCAT_HOST juz istnieje w $ZONE_FORWARD"
else
    log "Dodaje A record do $ZONE_FORWARD"
    serial_change=$(bump_serial "$ZONE_FORWARD")
    echo "${RCAT_HOST}      IN A    ${RCAT_IP}" >> "$ZONE_FORWARD"
    log "[OK] A record dodany. SOA serial: $serial_change"
fi

# 2) Reverse zone
if grep -q "^${RCAT_PTR_OCTET}[[:space:]]" "$ZONE_REVERSE"; then
    log "[skip] Wpis PTR dla $RCAT_PTR_OCTET juz istnieje w $ZONE_REVERSE"
else
    log "Dodaje PTR record do $ZONE_REVERSE"
    serial_change=$(bump_serial "$ZONE_REVERSE")
    echo "${RCAT_PTR_OCTET}          IN PTR  ${RCAT_FQDN}." >> "$ZONE_REVERSE"
    log "[OK] PTR record dodany. SOA serial: $serial_change"
fi

# 3) Reload named
log "Reload named..."
rndc reload 2>&1 | tee /tmp/rndc_reload.log
sleep 2

# 4) Walidacja
log "Walidacja przez dig..."
dig +short "$RCAT_FQDN" @127.0.0.1
dig +short -x "$RCAT_IP" @127.0.0.1

log "=== DNS dla rcat01 skonfigurowany ==="
