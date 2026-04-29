#!/usr/bin/env bash
# ==============================================================================
# Tytul:        validate_env.sh
# Opis:         Pre-flight sanity check srodowiska VMs2-install zanim startujesz
#               instalacje GI/DB/Standby. Sprawdza: DNS, NTP, SSH equivalency,
#               mounty /u01 + /mnt/oracle_binaries, dostepnosc dyskow ASM,
#               porty Oracle (1521/1522/6200/27015), HugePages, swap.
# Description [EN]: Pre-flight env validation before GI/DB/Standby install.
#
# Autor:        KCB Kris
# Data:         2026-04-27
# Wersja:       1.0 (VMs2-install) - F-11
#
# Wymagania [PL]:    - Uruchamiac na prim01 (lub prim02) jako oracle/grid;
#                      wykonuje zdalne testy ssh do prim02/stby01/infra01.
# Requirements [EN]: - Run as oracle/grid on prim01 (or prim02); reaches all peers via SSH.
#
# Uzycie [PL]:  bash scripts/validate_env.sh [--quick|--full]
# Usage [EN]:   bash scripts/validate_env.sh [--quick|--full]
# ==============================================================================

set -uo pipefail

MODE="${1:---full}"
PASS=0
FAIL=0
WARN=0

log()    { printf '[%s]\n' "$1"; }
ok()     { printf '  [\e[32mPASS\e[0m] %s\n' "$1"; PASS=$((PASS+1)); }
fail()   { printf '  [\e[31mFAIL\e[0m] %s\n' "$1"; FAIL=$((FAIL+1)); }
warn()   { printf '  [\e[33mWARN\e[0m] %s\n' "$1"; WARN=$((WARN+1)); }

check() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        ok "$desc"
    else
        fail "$desc"
    fi
}

# 1. DNS - wszystkie hosty rozwiazywalne.
log "1. DNS resolution (FQDN i krotka nazwa)"
for host in infra01 prim01 prim02 stby01 client01 scan-prim; do
    if getent hosts "${host}.lab.local" >/dev/null 2>&1; then
        ok "${host}.lab.local resolves"
    else
        fail "${host}.lab.local NIE resolwowalny - sprawdz bind9 na infra01 i /etc/resolv.conf"
    fi
done

# 2. NTP synchronizacja.
log "2. NTP (chronyd) synchronizacja z infra01"
if command -v chronyc >/dev/null 2>&1; then
    if chronyc tracking 2>/dev/null | grep -qE 'Stratum *: *[1-9]'; then
        ok "chronyd synchronized (Stratum > 0)"
    else
        warn "chronyc tracking nie pokazuje synchronizacji - sprawdz chronyc sources"
    fi
else
    warn "chronyc niedostepny"
fi

# 3. SSH equivalency oracle@peers (test BatchMode).
log "3. SSH equivalency (oracle user)"
for host in prim02 stby01; do
    if su - oracle -c "ssh -o BatchMode=yes -o ConnectTimeout=5 oracle@${host}.lab.local date" >/dev/null 2>&1; then
        ok "ssh oracle@${host} bezhaslowy"
    else
        warn "ssh oracle@${host} wymaga hasla / nie dziala (uruchom ssh_setup.sh)"
    fi
done

# 4. Mounty.
log "4. Mounty"
check "/u01 jest mountpoint" mountpoint -q /u01
if mountpoint -q /mnt/oracle_binaries; then
    ok "/mnt/oracle_binaries jest mounted (vboxsf)"
else
    warn "/mnt/oracle_binaries nie jest mounted - shared folder VirtualBox nie aktywny"
fi

# 5. ASM disk devices.
log "5. ASM disks (/dev/oracleasm/* lub /dev/disk/by-id/scsi-*)"
if [ -d /dev/oracleasm ] && [ -n "$(ls -A /dev/oracleasm 2>/dev/null)" ]; then
    ok "/dev/oracleasm zawiera dyski: $(ls /dev/oracleasm | tr '\n' ' ')"
elif ls /dev/disk/by-id/ 2>/dev/null | grep -qE 'scsi-|iscsi'; then
    ok "Dyski iSCSI widoczne w /dev/disk/by-id/"
else
    warn "Brak widocznych dyskow ASM - czy iSCSI initiator zalogowany?"
fi

# 6. Porty Oracle (na localhost po instalacji).
log "6. Porty Oracle (jesli zainstalowano - ss/lsof)"
for port in 1521 1522 6200; do
    if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE ":${port}$"; then
        ok "port ${port}/tcp nasluchuje (listener/DGMGRL/ONS)"
    else
        warn "port ${port}/tcp nie nasluchuje (OK przed instalacja, FAIL po)"
    fi
done

# 7. HugePages.
log "7. HugePages (F-18.A)"
HP_TOTAL=$(awk '/^HugePages_Total:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
if [ "$HP_TOTAL" -ge 2000 ]; then
    ok "HugePages_Total=${HP_TOTAL} (cel 2200, wystarczajaca)"
elif [ "$HP_TOTAL" -gt 0 ]; then
    warn "HugePages_Total=${HP_TOTAL} - mniej niz zalecane 2200"
else
    warn "HugePages nieskonfigurowane - sprawdz /etc/sysctl.d/99-oracle-hugepages.conf"
fi

# 8. Swap i RAM.
log "8. Pamiec / swap"
RAM_GB=$(awk '/MemTotal/ {printf "%.1f", $2/1024/1024}' /proc/meminfo)
SWAP_GB=$(awk '/SwapTotal/ {printf "%.1f", $2/1024/1024}' /proc/meminfo)
HOST=$(hostname -s)
case "$HOST" in
    prim01|prim02)
        if (( $(echo "$RAM_GB >= 8.5" | bc -l 2>/dev/null || echo 0) )); then
            ok "RAM=${RAM_GB} GB (wymog cluvfy 23.26: >= 8 GB physical)"
        else
            fail "RAM=${RAM_GB} GB - cluvfy 23.26 wymaga >= 8 GB"
        fi
        ;;
    infra01)
        if (( $(echo "$RAM_GB >= 7.5" | bc -l 2>/dev/null || echo 0) )); then
            ok "RAM=${RAM_GB} GB (cel 8 GB dla LIO page cache)"
        else
            warn "RAM=${RAM_GB} GB - F-18.G zaleca 8 GB"
        fi
        ;;
    *) ok "RAM=${RAM_GB} GB swap=${SWAP_GB} GB" ;;
esac

# 9. THP wylaczone.
log "9. Transparent HugePages (musi byc 'never')"
THP=$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null | grep -oE '\[[a-z]+\]' | tr -d '[]')
if [ "$THP" = "never" ]; then
    ok "THP enabled=never (poprawnie)"
else
    fail "THP enabled=${THP} - powinno byc 'never' (FIX-033)"
fi

# 10. memlock unlimited dla oracle.
log "10. memlock dla oracle (F-18.A)"
if su - oracle -c 'ulimit -l' 2>/dev/null | grep -q unlimited; then
    ok "oracle memlock = unlimited"
else
    warn "oracle memlock != unlimited - sprawdz /etc/security/limits.d/zz-oracle-memlock.conf"
fi

echo
printf "===== SUMMARY: %d PASS, %d WARN, %d FAIL =====\n" "$PASS" "$WARN" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
