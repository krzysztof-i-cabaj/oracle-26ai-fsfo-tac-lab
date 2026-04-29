#!/usr/bin/env bash
# ==============================================================================
# Tytul:        setup_dns_infra01.sh
# Opis:         Instaluje i konfiguruje bind9 na infra01 dla strefy lab.local.
#               Kickstart instaluje pakiet bind, ale nie tworzy zone files ani
#               named.conf — ten skrypt uzupelnia brakujaca konfiguracje.
# Description [EN]: Install and configure bind9 DNS on infra01 for lab.local.
#               Kickstart installs bind but leaves no zone files or named.conf
#               — this script fills in the missing configuration.
#
# Autor:        KCB Kris
# Data:         2026-04-28
# Wersja:       1.0 (VMs2-install — port z VMs/scripts/setup_dns_infra01.sh)
#
# Wymagania [PL]:    - root, uruchomione na infra01 (192.168.56.10)
#                    - bind i bind-utils zainstalowane (kickstart to robi)
# Requirements [EN]: - root, run on infra01 (192.168.56.10)
#                    - bind and bind-utils installed (kickstart handles this)
#
# Uzycie [PL]:       sudo bash <repo>/scripts/setup_dns_infra01.sh
# Usage [EN]:        sudo bash <repo>/scripts/setup_dns_infra01.sh
# ==============================================================================

set -euo pipefail
log() { echo "[$(date +%H:%M:%S)] $*"; }

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: wymaga root"
    exit 1
fi

HOSTNAME=$(hostname -s)
if [[ "$HOSTNAME" != "infra01" ]]; then
    echo "WARN: Hostname to '$HOSTNAME' zamiast 'infra01'. Ten skrypt powinien dzialac tylko na infra01."
    read -r -p "Kontynuuj mimo to? (y/N) " continue_anyway
    if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

log "Sprawdzam bind..."
dnf install -y bind bind-utils

log "Backup istniejacej konfiguracji..."
cp -n /etc/named.conf /etc/named.conf.bak 2>/dev/null || true

log "Zapisywanie /etc/named.conf..."
cat > /etc/named.conf <<'EOF'
options {
    listen-on port 53 { 127.0.0.1; 192.168.56.10; };
    listen-on-v6 port 53 { none; };
    directory     "/var/named";
    dump-file     "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";
    allow-query   { localhost; 192.168.56.0/24; 192.168.100.0/24; 192.168.200.0/24; };
    recursion yes;
    forwarders    { 8.8.8.8; 1.1.1.1; };
    forward first;
    dnssec-validation auto;
};

logging {
    channel default_debug {
        file "data/named.run";
        severity dynamic;
    };
};

zone "." IN {
    type hint;
    file "named.ca";
};

zone "lab.local" IN {
    type master;
    file "db.lab.local";
    allow-update { none; };
};

zone "56.168.192.in-addr.arpa" IN {
    type master;
    file "db.56.168.192";
    allow-update { none; };
};

zone "100.168.192.in-addr.arpa" IN {
    type master;
    file "db.100.168.192";
    allow-update { none; };
};
EOF

log "Zapisywanie zone files..."

cat > /var/named/db.lab.local <<'EOF'
$TTL 86400
@           IN SOA  infra01.lab.local. admin.lab.local. (
                    2026042801 3600 900 1209600 3600 )
            IN NS   infra01.lab.local.

; --- Hosty / Hosts ---
infra01     IN A    192.168.56.10
prim01      IN A    192.168.56.11
prim02      IN A    192.168.56.12
stby01      IN A    192.168.56.13
client01    IN A    192.168.56.15

; --- VIP (Oracle RAC) ---
prim01-vip  IN A    192.168.56.21
prim02-vip  IN A    192.168.56.22

; --- SCAN (3 adresy round-robin dla 2-node RAC) ---
scan-prim   IN A    192.168.56.31
scan-prim   IN A    192.168.56.32
scan-prim   IN A    192.168.56.33

; --- Prywatne (interconnect) ---
prim01-priv  IN A   192.168.100.11
prim02-priv  IN A   192.168.100.12
infra01-priv IN A   192.168.100.10

; --- Storage (iSCSI) ---
prim01-stor  IN A   192.168.200.11
prim02-stor  IN A   192.168.200.12
infra01-stor IN A   192.168.200.10
EOF

cat > /var/named/db.56.168.192 <<'EOF'
$TTL 86400
@           IN SOA  infra01.lab.local. admin.lab.local. (
                    2026042801 3600 900 1209600 3600 )
            IN NS   infra01.lab.local.

10          IN PTR  infra01.lab.local.
11          IN PTR  prim01.lab.local.
12          IN PTR  prim02.lab.local.
13          IN PTR  stby01.lab.local.
15          IN PTR  client01.lab.local.
21          IN PTR  prim01-vip.lab.local.
22          IN PTR  prim02-vip.lab.local.
31          IN PTR  scan-prim.lab.local.
32          IN PTR  scan-prim.lab.local.
33          IN PTR  scan-prim.lab.local.
EOF

cat > /var/named/db.100.168.192 <<'EOF'
$TTL 86400
@           IN SOA  infra01.lab.local. admin.lab.local. (
                    2026042801 3600 900 1209600 3600 )
            IN NS   infra01.lab.local.

10          IN PTR  infra01-priv.lab.local.
11          IN PTR  prim01-priv.lab.local.
12          IN PTR  prim02-priv.lab.local.
EOF

chown root:named /var/named/db.lab.local /var/named/db.56.168.192 /var/named/db.100.168.192
chmod 640 /var/named/db.lab.local /var/named/db.56.168.192 /var/named/db.100.168.192

log "Weryfikacja skladni..."
named-checkconf && log "named.conf OK" || { log "named.conf BLAD!"; exit 1; }
named-checkzone lab.local /var/named/db.lab.local
named-checkzone 56.168.192.in-addr.arpa /var/named/db.56.168.192
named-checkzone 100.168.192.in-addr.arpa /var/named/db.100.168.192

log "Otwieranie firewall..."
firewall-cmd --permanent --zone=public --add-service=dns 2>/dev/null || true
firewall-cmd --permanent --zone=trusted --add-source=192.168.100.0/24 2>/dev/null || true
firewall-cmd --permanent --zone=trusted --add-source=192.168.200.0/24 2>/dev/null || true
firewall-cmd --reload 2>/dev/null || true

log "Start uslugi named..."
systemctl enable --now named

log "Test DNS..."
sleep 2
for q in infra01 prim01 prim02 stby01 client01 scan-prim; do
    result=$(dig @192.168.56.10 ${q}.lab.local +short | head -1)
    log "  ${q}.lab.local -> ${result:-FAIL}"
done

log "Test reverse (prim01)..."
dig @192.168.56.10 -x 192.168.56.11 +short

# Wymusz 127.0.0.1 jako DNS na infra01 (DHCP NAT moze nadpisywac resolv.conf).
log "Wymuszam 127.0.0.1 jako DNS w NetworkManager na infra01..."
nmcli connection modify "System enp0s10" ipv4.ignore-auto-dns yes 2>/dev/null || true
nmcli connection modify "System enp0s3"  ipv4.dns "127.0.0.1"        2>/dev/null || true
nmcli connection modify "System enp0s3"  ipv4.dns-search "lab.local" 2>/dev/null || true
nmcli connection modify "System enp0s3"  ipv4.ignore-auto-dns yes    2>/dev/null || true
nmcli connection down "System enp0s10" >/dev/null 2>&1 || true
nmcli connection up   "System enp0s10" >/dev/null 2>&1 || true
nmcli connection down "System enp0s3"  >/dev/null 2>&1 || true
nmcli connection up   "System enp0s3"  >/dev/null 2>&1 || true
sleep 2

log "Finalny /etc/resolv.conf na infra01:"
cat /etc/resolv.conf

log "Test DNS przez resolwer systemowy:"
nslookup scan-prim.lab.local 2>&1 | grep -E "^(Server|Address|Name)" | head -6

log "Done."
log "Nastepny krok: na prim01/prim02/stby01/client01 uruchom:"
log "  sudo bash <repo>/scripts/setup_chrony.sh --role=client"
log "To naprawi DNS resolwer (192.168.56.10) i NTP (infra01) na kazdej maszynie."
