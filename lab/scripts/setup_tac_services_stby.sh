#!/usr/bin/env bash
# ==============================================================================
# Tytul:        setup_tac_services_stby.sh
# Opis:         Rejestracja serwisu MYAPP_TAC w Oracle Restart na stby01.
#               Bazuje na fakcie ze stby01 ma Grid Infrastructure for Standalone
#               Server (CRS na poziomie hosta), wiec po failover Oracle Restart
#               sam moze startowac serwis z atrybutem -role PRIMARY (analogicznie
#               jak Grid CRS na klastrze RAC). Rejestrujemy serwis tu, by NIE musiec
#               wywolywac DBMS_SERVICE.START_SERVICE recznie po awarii.
# Description [EN]: Register MYAPP_TAC on stby01 Oracle Restart so that after
#               failover the local CRS auto-starts the service (analog to GI Cluster
#               on RAC). Eliminates the need for manual DBMS_SERVICE.START_SERVICE
#               (FIX-095 fallback in tac_service_resume.sh stays as last resort).
#
# Autor:        KCB Kris
# Data:         2026-04-27
# Wersja:       1.0 (VMs2-install) - F-13/Oracle Restart awareness
#
# Wymagania [PL]:    - Uruchamiac na stby01 jako oracle (po stworzeniu standby db).
#                    - Baza STBY musi byc zarejestrowana w Oracle Restart przez:
#                        srvctl add database -db STBY -oraclehome ... -role PHYSICAL_STANDBY
#                      (zob. doc 06_Data_Guard_Standby.md po DUPLICATE).
# Requirements [EN]: - Run on stby01 as oracle, after standby DB exists in Oracle Restart.
#
# Uzycie [PL]:  ssh oracle@stby01 'bash <repo>/scripts/setup_tac_services_stby.sh'
# Usage [EN]:   see above.
# ==============================================================================

set -euo pipefail

DB_NAME="${DB_NAME:-STBY}"
PDB_NAME="${PDB_NAME:-APPPDB}"
SERVICE_NAME="${SERVICE_NAME:-MYAPP_TAC}"

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
echo "  TAC service rejestrowany w Oracle Restart na $(hostname)"
echo "  DB=${DB_NAME}  PDB=${PDB_NAME}  SERVICE=${SERVICE_NAME}"
echo "=========================================================="

# 1. Sanity check: Oracle Restart musi miec zarejestrowana baze STBY.
if ! srvctl config database -db "$DB_NAME" >/dev/null 2>&1; then
    cat <<ERREOF
[FATAL] Baza ${DB_NAME} nie jest zarejestrowana w Oracle Restart.
        Najpierw wykonaj (przyklad):
          srvctl add database -db ${DB_NAME} \\
              -oraclehome /u01/app/oracle/product/23.26/dbhome_1 \\
              -role PHYSICAL_STANDBY \\
              -startoption MOUNT \\
              -dbtype SINGLE \\
              -domain lab.local
ERREOF
    exit 1
fi

# 2. Idempotency: jesli serwis juz istnieje na Oracle Restart - modify; inaczej add.
if srvctl config service -db "$DB_NAME" -service "$SERVICE_NAME" >/dev/null 2>&1; then
    echo "[INFO] Serwis ${SERVICE_NAME} istnieje w Oracle Restart - srvctl modify..."
    srvctl modify service -db "$DB_NAME" -service "$SERVICE_NAME" "${TAC_FLAGS[@]}"
else
    echo "[INFO] Serwis ${SERVICE_NAME} nieobecny - srvctl add..."
    srvctl add service -db "$DB_NAME" -service "$SERVICE_NAME" \
        -pdb "$PDB_NAME" "${TAC_FLAGS[@]}"
fi

# 3. -role PRIMARY oznacza ze Oracle Restart wystartuje serwis TYLKO gdy DB jest PRIMARY.
#    Po failover STBY->PRIMARY: CRS automatycznie podejmie start. Brak manual interwencji.
#    Przed failover (rola PHYSICAL_STANDBY): serwis jest config-only, NIE running.
echo "[INFO] Serwis zarejestrowany z -role PRIMARY - aktywuje sie automatycznie po failover."

# 4. Weryfikacja konfiguracji.
echo
echo "Konfiguracja serwisu w Oracle Restart na $(hostname):"
srvctl config service -db "$DB_NAME" -service "$SERVICE_NAME" | \
    grep -E 'Pluggable|Failover type|Failover restore|Commit Outcome|Retention|Drain|Session State|Notification|Management policy|Service role'

cat <<INFO

NASTEPSTWO:
  - Po unplanned failover (Scenariusz 2 z docs/09): Oracle Restart auto-startuje
    serwis na stby01 w ciagu 5-15 s. Skrypt tac_service_resume.sh staje sie
    fallback-iem (idempotentny - mozna uruchomic dla pewnosci).
  - Bezposrednio po stworzeniu standby (doc 06): serwis nie jest jeszcze running,
    bo stby01 ma role PHYSICAL_STANDBY. To jest oczekiwane.
  - Po SWITCHOVER: Oracle Restart wykryje zmiane roli i wystartuje serwis.

WERYFIKACJA POST-FAILOVER:
  srvctl status service -db ${DB_NAME} -service ${SERVICE_NAME}
  # Po promote: 'Service ${SERVICE_NAME} is running on database ${DB_NAME}'
INFO
