#!/bin/bash
# Skrypt: setup_tac_services.sh | Script: setup_tac_services.sh
# Cel: Utworzenie i start serwisu MYAPP_TAC pod Application Continuity / Goal: Create and start MYAPP_TAC service for Application Continuity
# Uruchamiac na: prim01 jako uzytkownik oracle / Run on: prim01 as oracle user

set -euo pipefail

DB_NAME="${DB_NAME:-PRIM}"
PDB_NAME="${PDB_NAME:-APPPDB}"
SERVICE_NAME="${SERVICE_NAME:-MYAPP_TAC}"
PREF_INSTANCES="${PREF_INSTANCES:-PRIM1,PRIM2}"

# Wspolne flagi (tablica - kolejnosc nie ma znaczenia, srvctl rozumie kazda).
# Common flags array - srvctl accepts them in any order.
TAC_FLAGS=(
    -failovertype TRANSACTION
    -failover_restore LEVEL1
    -commit_outcome TRUE
    -session_state DYNAMIC
    -retention 86400
    -replay_init_time 1800
    -drain_timeout 300
    -stopoption IMMEDIATE
    -role PRIMARY
    -notification TRUE
    -rlbgoal SERVICE_TIME
    -clbgoal SHORT
    -failoverretry 30
    -failoverdelay 10
    -policy AUTOMATIC
)

echo "=========================================================="
echo "    Konfiguracja TAC Service (${SERVICE_NAME})            "
echo "    TAC Service Configuration (${SERVICE_NAME})           "
echo "=========================================================="

# F-12: idempotency - jesli serwis juz istnieje, robimy modify zamiast add.
# F-12: idempotency - if service exists, modify instead of add.
if srvctl config service -db "$DB_NAME" -service "$SERVICE_NAME" >/dev/null 2>&1; then
    echo "1. Serwis ${SERVICE_NAME} istnieje - wykonuje srvctl modify... / 1. Service exists - running srvctl modify..."
    srvctl modify service -db "$DB_NAME" -service "$SERVICE_NAME" "${TAC_FLAGS[@]}"
else
    echo "1. Rejestracja nowego serwisu w klastrze RAC (${PREF_INSTANCES})... / 1. Registering new service..."
    srvctl add service -db "$DB_NAME" -service "$SERVICE_NAME" \
        -preferred "$PREF_INSTANCES" -pdb "$PDB_NAME" "${TAC_FLAGS[@]}"
fi

echo "2. Uruchamianie serwisu ${SERVICE_NAME}... / 2. Starting service..."
# srvctl start moze zwrocic CRS-2613/CRS-2640 jesli juz uruchomiony - ignorujemy.
# srvctl start may return CRS-2613/CRS-2640 if already running - benign.
srvctl start service -db "$DB_NAME" -service "$SERVICE_NAME" 2>&1 | grep -vE 'CRS-2613|CRS-2640' || true

echo "3. Weryfikacja statusu i konfiguracji na PRIM... / 3. Verifying PRIM status..."
srvctl status service -db "$DB_NAME" -service "$SERVICE_NAME"
echo
srvctl config service -db "$DB_NAME" -service "$SERVICE_NAME" | \
  grep -E 'Pluggable|Failover type|Failover restore|Commit Outcome|Retention|Drain|Session State|Notification' || true

# 4. Rejestracja w Oracle Restart na stby01 (kluczowa dla post-failover auto-start).
#    Skrypt setup_tac_services_stby.sh musi byc dostepny na stby01 (np. /tmp/scripts/).
#    Jesli SKIP_STBY=1, ten krok pomijamy (np. gdy stby01 nie istnieje jeszcze).
# 4. Register on stby01 Oracle Restart (critical for post-failover auto-start).
if [ "${SKIP_STBY:-0}" != "1" ]; then
    echo
    echo "4. Rejestracja serwisu w Oracle Restart na stby01... / 4. Registering on stby01 Oracle Restart..."
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if ssh -o BatchMode=yes -o ConnectTimeout=5 oracle@stby01 'true' >/dev/null 2>&1; then
        scp -q "${SCRIPT_DIR}/setup_tac_services_stby.sh" oracle@stby01:/tmp/setup_tac_services_stby.sh
        ssh oracle@stby01 ". ~/.bash_profile && bash /tmp/setup_tac_services_stby.sh" || \
            echo "[WARN] Rejestracja na stby01 nieudana — uruchom recznie: ssh oracle@stby01 'bash <repo>/scripts/setup_tac_services_stby.sh'"
    else
        echo "[WARN] SSH oracle@stby01 niedostepny — uruchom recznie z stby01: bash <repo>/scripts/setup_tac_services_stby.sh"
    fi
else
    echo "[INFO] SKIP_STBY=1 — pomijam rejestracje na stby01."
fi
