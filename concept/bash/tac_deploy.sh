#!/bin/bash
# ==============================================================================
# Tytul:        tac_deploy.sh
# Opis:         Deployment TAC service na klastrze RAC.
#               Generuje komendy srvctl przez sql/tac_configure_service_rac.sql.
#               Tryb -d (dry-run) tylko drukuje komendy.
# Description [EN]: TAC service deployment on RAC cluster.
#                   Generates srvctl commands via sql/tac_configure_service_rac.sql.
#                   Dry-run mode (-d) prints commands only.
#
# Autor:        KCB Kris
# Data:         2026-04-23
# Wersja:       1.0
#
# Wymagania [PL]:    - sqlconn.sh w PATH
#                    - Uruchamiac na RAC node (srvctl w PATH)
#                    - Uprawnienia oracle user + sudo na srvctl (jesli wymagane)
# Requirements [EN]: - sqlconn.sh in PATH
#                    - Run on RAC node (srvctl in PATH)
#                    - oracle user + sudo on srvctl (if required)
#
# Uzycie [PL]:       ./tac_deploy.sh -s PRIM [-d] [-v MYAPP_TAC]
# Usage [EN]:        ./tac_deploy.sh -s PRIM [-d] [-v MYAPP_TAC]
# ==============================================================================

set -euo pipefail

# --- Konfiguracja ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( dirname "$SCRIPT_DIR" )"
LOG_DIR="${PROJECT_DIR}/logs"
REPORTS_DIR="${PROJECT_DIR}/reports"

DATE_TAG=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/tac_deploy_${DATE_TAG}.log"

# --- Kolory ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Domyslne ---
DRY_RUN=0
EXECUTE_MODE=0
SERVICE_BASE=""
TAC_SERVICE_NAME=""
PREFERRED_INST=""
AVAILABLE_INST=""
ONS_REMOTE=""

usage() {
    cat <<EOF
==============================================================================
   TAC Service Deployment (tac_deploy.sh) v1.1
==============================================================================
Uzycie / Usage: $0 -s <service> [-d | -x] [-v <name>] [-p <pref>] [-i <avail>] [-n <ons>]

Wymagane / Required:
  -s <service>    Nazwa bazy (np. PRIM). Uzyte w srvctl -d <service>.

Opcjonalne / Optional:
  -d              Dry-run: tylko wypisz komendy srvctl (nie wykonuj)
  -x              Execute: wykonuje srvctl add service + modify ons
                  (wymaga -p, opcjonalnie -i, -n)
  -v <name>       Nazwa TAC service (domyslnie: MYAPP_TAC)
  -p <pref>       Preferred instances (np. "PRIM1,PRIM2") - wymagane z -x
  -i <avail>      Available instances (np. "PRIM3") - opcjonalne
  -n <ons>        Remote ONS servers (np. "host1:6200,host2:6200") - opcjonalne

Co robi / What it does:
  1. Uruchamia sql/tac_configure_service_rac.sql (generator)
  2. Zapisuje wynik do reports/ jako komendy srvctl
  3. Domyslnie: wymaga manual apply przez DBA
  4. -x: wykonuje srvctl add service z parametrami TAC + konfiguracja ONS

Przyklady / Examples:
  Dry-run:    $0 -s PRIM -d
  Generator:  $0 -s PRIM
  Apply:      $0 -s PRIM -x -v MYAPP_TAC -p "PRIM1,PRIM2" \\
                -n "host-dc:6200,host-dr:6200,host-ext:6200"
==============================================================================
EOF
    exit 1
}

log_msg() {
    local msg="$1"
    local level="${2:-INFO}"
    local ts=$(date "+%Y-%m-%d %H:%M:%S")
    mkdir -p "$LOG_DIR"
    echo "[$ts] [$level] $msg" >> "$LOG_FILE"
    case $level in
        "ERROR") echo -e "${RED}[ERROR] $msg${NC}" >&2 ;;
        "WARN")  echo -e "${YELLOW}[WARN]  $msg${NC}" ;;
        "OK")    echo -e "${GREEN}[OK]    $msg${NC}" ;;
        *)       echo -e "${CYAN}[INFO]  $msg${NC}" ;;
    esac
}

# --- Pre-flight ---
if [ $# -eq 0 ]; then usage; fi

while getopts "s:dxv:p:i:n:" opt; do
    case ${opt} in
        s) SERVICE_BASE=$OPTARG ;;
        d) DRY_RUN=1 ;;
        x) EXECUTE_MODE=1 ;;
        v) TAC_SERVICE_NAME=$OPTARG ;;
        p) PREFERRED_INST=$OPTARG ;;
        i) AVAILABLE_INST=$OPTARG ;;
        n) ONS_REMOTE=$OPTARG ;;
        *) usage ;;
    esac
done

if [ -z "$SERVICE_BASE" ]; then
    echo -e "${RED}Blad: nie podano -s${NC}"
    usage
fi

if [ "$EXECUTE_MODE" -eq 1 ] && [ "$DRY_RUN" -eq 1 ]; then
    echo -e "${RED}Blad: -d i -x sa wzajemnie wykluczajace${NC}"
    usage
fi

if [ "$EXECUTE_MODE" -eq 1 ] && [ -z "$PREFERRED_INST" ]; then
    echo -e "${RED}Blad: tryb -x wymaga -p <preferred_instances>${NC}"
    usage
fi

if [ "$EXECUTE_MODE" -eq 1 ] && ! command -v srvctl >/dev/null 2>&1; then
    echo -e "${RED}Blad: srvctl NIE w PATH (wymagany dla -x)${NC}"
    exit 2
fi

TAC_SERVICE_NAME="${TAC_SERVICE_NAME:-MYAPP_TAC}"

if ! command -v sqlconn.sh >/dev/null 2>&1; then
    log_msg "sqlconn.sh NIE w PATH" "ERROR"
    exit 2
fi

mkdir -p "$LOG_DIR" "$REPORTS_DIR"

log_msg "TAC Deployment — start" "INFO"
log_msg "Service: $SERVICE_BASE | TAC service name: $TAC_SERVICE_NAME | Dry-run: $DRY_RUN" "INFO"

# ============================================================================
# KROK 1: Generator srvctl commands
# ============================================================================

log_msg "=== KROK 1: Generator srvctl commands ===" "INFO"
SRVCTL_SCRIPT="${REPORTS_DIR}/tac_srvctl_${SERVICE_BASE}_${DATE_TAG}.sh"

log_msg "Uruchamiam: sqlconn.sh -s $SERVICE_BASE -i -f sql/tac_configure_service_rac.sql" "INFO"

sqlconn.sh -s "$SERVICE_BASE" \
           -i \
           -f "${PROJECT_DIR}/sql/tac_configure_service_rac.sql" \
           -o "$SRVCTL_SCRIPT" \
    || { log_msg "Generator SQL FAILED" "ERROR"; exit 3; }

log_msg "srvctl commands wygenerowane: $SRVCTL_SCRIPT" "OK"

# ============================================================================
# KROK 2: Review + (opcjonalnie) apply
# ============================================================================

echo ""
echo -e "${YELLOW}==============================================================================${NC}"
echo -e "${YELLOW} KROK 2: Review i apply${NC}"
echo -e "${YELLOW}==============================================================================${NC}"
echo ""
echo "  Wygenerowany skrypt srvctl:"
echo "     $SRVCTL_SCRIPT"
echo ""

if [ "$DRY_RUN" -eq 1 ]; then
    echo -e "  ${CYAN}Dry-run - NIE wykonano zadnych zmian.${NC}"
    echo "  Po review, uruchom:"
    echo -e "     ${CYAN}$0 -s $SERVICE_BASE -x -p \"${SERVICE_BASE}1,${SERVICE_BASE}2\"${NC}"
    echo ""
    echo -e "${YELLOW}==============================================================================${NC}"
    log_msg "Dry-run zakonczony. Plik: $SRVCTL_SCRIPT" "OK"
    exit 0
fi

if [ "$EXECUTE_MODE" -eq 0 ]; then
    # Tryb generator (domyslny): tylko instrukcje dla DBA
    echo -e "${YELLOW}  Tryb generator - srvctl NIE jest wywolywany automatycznie.${NC}"
    echo ""
    echo "  Prosze:"
    echo -e "     ${CYAN}1. Przejrzyj $SRVCTL_SCRIPT${NC}"
    echo -e "     ${CYAN}2. Wyekstrahuj komendy srvctl (z bloku PL/SQL DBMS_OUTPUT)${NC}"
    echo -e "     ${CYAN}3. Uruchom jako oracle user na RAC node, lub uzyj -x:${NC}"
    echo -e "     ${GREEN}$0 -s $SERVICE_BASE -x -p \"${SERVICE_BASE}1,${SERVICE_BASE}2\"${NC}"
    echo ""
    echo -e "${YELLOW}==============================================================================${NC}"
    log_msg "Generator zakonczony. Uzyj -x aby zastosowac lub apply recznie." "OK"
    exit 0
fi

# ============================================================================
# TRYB EXECUTE (-x): faktyczne srvctl add service + ONS
# ============================================================================

log_msg "=== KROK 3: srvctl add service $TAC_SERVICE_NAME ===" "INFO"

# Idempotencja: sprawdz czy service juz istnieje
if srvctl status service -d "$SERVICE_BASE" -s "$TAC_SERVICE_NAME" >/dev/null 2>&1; then
    log_msg "Service $TAC_SERVICE_NAME juz istnieje na $SERVICE_BASE" "WARN"
    log_msg "Aby odtworzyc: srvctl stop service + remove service recznie." "WARN"
    log_msg "Status biezacy:" "INFO"
    srvctl status service -d "$SERVICE_BASE" -s "$TAC_SERVICE_NAME" || true
    exit 0
fi

# Budowa komendy srvctl
SRVCTL_CMD=(srvctl add service
    -db          "$SERVICE_BASE"
    -service     "$TAC_SERVICE_NAME"
    -preferred   "$PREFERRED_INST"
    -failovertype    TRANSACTION
    -failover_restore LEVEL1
    -commit_outcome  TRUE
    -failoverretry   30
    -failoverdelay   10
    -replay_init_time 1800
    -retention       86400
    -session_state   DYNAMIC
    -drain_timeout   300
    -stopoption      IMMEDIATE
    -role            PRIMARY
    -notification    TRUE
    -clbgoal         SHORT
    -rlbgoal         SERVICE_TIME
)

if [ -n "$AVAILABLE_INST" ]; then
    SRVCTL_CMD+=(-available "$AVAILABLE_INST")
fi

log_msg "Wywolanie: ${SRVCTL_CMD[*]}" "INFO"
if "${SRVCTL_CMD[@]}" >>"$LOG_FILE" 2>&1; then
    log_msg "srvctl add service OK" "OK"
else
    SRV_RC=$?
    log_msg "srvctl add service FAILED (rc=$SRV_RC) - sprawdz $LOG_FILE" "ERROR"
    tail -20 "$LOG_FILE" >&2
    exit 4
fi

# Konfiguracja ONS (opcjonalnie)
if [ -n "$ONS_REMOTE" ]; then
    log_msg "=== KROK 4: srvctl modify ons -remoteservers $ONS_REMOTE ===" "INFO"
    if srvctl modify ons -remoteservers "$ONS_REMOTE" >>"$LOG_FILE" 2>&1; then
        log_msg "ONS remoteservers zaktualizowany" "OK"
    else
        log_msg "ONS modify FAILED - kontynuacja (nie-krytyczne dla startu service)" "WARN"
    fi
else
    log_msg "Pominieto konfiguracje ONS (brak -n). FAN moze nie dochodzic do klientow!" "WARN"
fi

# Start service
log_msg "=== KROK 5: srvctl start service $TAC_SERVICE_NAME ===" "INFO"
if srvctl start service -db "$SERVICE_BASE" -service "$TAC_SERVICE_NAME" >>"$LOG_FILE" 2>&1; then
    log_msg "Service $TAC_SERVICE_NAME uruchomiony" "OK"
else
    log_msg "Service start FAILED - sprawdz $LOG_FILE" "ERROR"
    exit 5
fi

# Weryfikacja
log_msg "Status:" "INFO"
srvctl status service -d "$SERVICE_BASE" -s "$TAC_SERVICE_NAME" | tee -a "$LOG_FILE"

log_msg "TAC deployment zakonczony." "OK"
exit 0
