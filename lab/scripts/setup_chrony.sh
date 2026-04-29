#!/usr/bin/env bash
# ==============================================================================
# Tytul:        setup_chrony.sh
# Opis:         Konfiguruje chrony w trybie serwer (infra01) lub klient (pozostale VM).
#               W trybie --role=client naprawia rowniez resolwer DNS (enp0s3 -> 192.168.56.10).
# Description [EN]: Configures chrony as NTP server (infra01) or client (other VMs).
#               In --role=client mode also fixes DNS resolver (enp0s3 -> 192.168.56.10).
#
# Autor:        KCB Kris
# Data:         2026-04-28
# Wersja:       1.0 (VMs2-install — port z VMs/scripts/setup_chrony.sh)
#
# Wymagania [PL]:    - root
#                    - dla --role=server: uruchomione na infra01; DNS juz skonfigurowany
#                    - dla --role=client: bind9 na infra01 juz dziala (setup_dns_infra01.sh)
# Requirements [EN]: - root; for server: infra01; for client: infra01 DNS must be up first
#
# Uzycie [PL]:       sudo bash <repo>/scripts/setup_chrony.sh --role=server    # na infra01
#                    sudo bash <repo>/scripts/setup_chrony.sh --role=client    # na prim01/prim02/stby01/client01
# Usage [EN]:        sudo bash <repo>/scripts/setup_chrony.sh --role=server|client
# ==============================================================================

set -euo pipefail
log() { echo "[$(date +%H:%M:%S)] $*"; }

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: wymaga root"
    exit 1
fi

ROLE=""
for arg in "$@"; do
    case $arg in
        --role=*)   ROLE="${arg#*=}" ;;
        -h|--help)  echo "Uzycie: sudo bash setup_chrony.sh --role=server|client"; exit 0 ;;
        *)          echo "ERROR: nieznany argument: $arg"; exit 1 ;;
    esac
done

if [[ -z "$ROLE" || ( "$ROLE" != "server" && "$ROLE" != "client" ) ]]; then
    echo "ERROR: --role=server lub --role=client wymagane"
    exit 1
fi

log "Instalacja chrony..."
dnf install -y chrony

log "Backup /etc/chrony.conf..."
cp -n /etc/chrony.conf /etc/chrony.conf.bak 2>/dev/null || true

if [[ "$ROLE" == "server" ]]; then
    HOSTNAME_SHORT=$(hostname -s)
    if [[ "$HOSTNAME_SHORT" != "infra01" ]]; then
        echo "WARN: Hostname to '$HOSTNAME_SHORT' zamiast 'infra01'."
        read -r -p "Kontynuuj mimo to? (y/N) " cont
        [[ "$cont" =~ ^[Yy]$ ]] || exit 1
    fi

    log "Konfiguracja trybu SERVER (infra01 — serwer NTP dla lab.local)..."
    cat > /etc/chrony.conf <<'EOF'
# ==============================================================================
# chrony.conf — infra01 jako serwer NTP dla lab.local
# ==============================================================================
pool pool.ntp.org iburst maxsources 4

# Zezwol klientom w sieciach labowych synchronizowac sie z nami
allow 192.168.56.0/24
allow 192.168.100.0/24
allow 192.168.200.0/24

# Udostepniaj czas nawet gdy sami jeszcze sie nie zsynchronizowalismy
local stratum 10

driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
leapsectz right/UTC
keyfile /etc/chrony.keys
logdir /var/log/chrony
EOF

    log "Otwieranie firewall dla NTP (UDP 123)..."
    firewall-cmd --permanent --zone=public --add-service=ntp 2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true

elif [[ "$ROLE" == "client" ]]; then
    log "Konfiguracja trybu CLIENT — synchronizacja z infra01.lab.local..."

    # Naprawa resolwera DNS: wymus 192.168.56.10 (infra01) na NIC host-only.
    # DHCP NAT (enp0s10 dla prim01/prim02/infra01, enp0s8 dla stby01/client01)
    # moze nadpisywac resolv.conf adresem routera LAN (nie zna lab.local).
    log "Wymuszam 192.168.56.10 jako DNS w NetworkManager (enp0s3)..."
    for nat_dev in enp0s10 enp0s8; do
        if nmcli -g DEVICE connection show --active 2>/dev/null | grep -q "^${nat_dev}$"; then
            nmcli connection modify "System ${nat_dev}" ipv4.ignore-auto-dns yes 2>/dev/null || true
        fi
    done
    nmcli connection modify "System enp0s3" ipv4.dns "192.168.56.10"  2>/dev/null || true
    nmcli connection modify "System enp0s3" ipv4.dns-search "lab.local" 2>/dev/null || true
    nmcli connection modify "System enp0s3" ipv4.ignore-auto-dns yes  2>/dev/null || true
    for dev in enp0s10 enp0s8 enp0s3; do
        if nmcli -g DEVICE connection show --active 2>/dev/null | grep -q "^${dev}$"; then
            nmcli connection down "System ${dev}" >/dev/null 2>&1 || true
            nmcli connection up   "System ${dev}" >/dev/null 2>&1 || true
        fi
    done
    sleep 2

    if ! getent hosts infra01.lab.local > /dev/null 2>&1; then
        echo "WARN: infra01.lab.local nie resolwuje sie po zmianie DNS."
        echo "      Sprawdz: cat /etc/resolv.conf  (powinno byc 'nameserver 192.168.56.10')"
        echo "      Lub: czy setup_dns_infra01.sh zostal uruchomiony na infra01?"
        read -r -p "Kontynuuj mimo to? (y/N) " cont
        [[ "$cont" =~ ^[Yy]$ ]] || exit 1
    fi

    cat > /etc/chrony.conf <<'EOF'
# ==============================================================================
# chrony.conf — klient NTP synchronizujacy z infra01.lab.local
# ==============================================================================
server infra01.lab.local iburst prefer

driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
leapsectz right/UTC
keyfile /etc/chrony.keys
logdir /var/log/chrony
EOF
fi

log "Restart i enable chronyd..."
systemctl enable --now chronyd
systemctl restart chronyd

log "Oczekiwanie 5 sekund na synchronizacje..."
sleep 5

log "chronyc sources:"
chronyc sources || true
echo

log "chronyc tracking:"
chronyc tracking || true

log "Done. Role: $ROLE"
if [[ "$ROLE" == "server" ]]; then
    log "Serwer nasluchuje na UDP 123. Klienci: synchronizuj z 'infra01.lab.local iburst prefer'"
else
    log "Klient: DNS = 192.168.56.10, NTP = infra01.lab.local"
    log "Weryfikacja DNS: dig prim02.lab.local  (powinno zwracac 192.168.56.12)"
fi
