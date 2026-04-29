#!/bin/bash
# ==============================================================================
# Tytul:        fsfo_setup.sh
# Opis:         Orkiestrator setupu FSFO - wola readiness check + generator broker + FSFO properties.
#               Tryb dry-run (-d) wypisuje komendy bez wykonania.
# Description [EN]: FSFO setup orchestrator - runs readiness check + broker generator + FSFO properties.
#                   Dry-run mode (-d) prints commands without executing.
#
# Autor:        KCB Kris
# Data:         2026-04-23
# Wersja:       1.0
#
# Wymagania [PL]:    - sqlconn.sh w PATH (z projektu 20260130-sqlconn)
#                    - Oracle 19c+ EE z wlaczonym DG Broker
#                    - Uruchamiac z konta DBA (SYSDBA)
# Requirements [EN]: - sqlconn.sh in PATH (from 20260130-sqlconn project)
#                    - Oracle 19c+ EE with DG Broker enabled
#                    - Run as DBA account (SYSDBA)
#
# Uzycie [PL]:       ./fsfo_setup.sh -s PRIM [-d]
# Usage [EN]:        ./fsfo_setup.sh -s PRIM [-d]
# ==============================================================================

set -euo pipefail

# --- Konfiguracja ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( dirname "$SCRIPT_DIR" )"
LOG_DIR="${PROJECT_DIR}/logs"
REPORTS_DIR="${PROJECT_DIR}/reports"

DATE_TAG=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/fsfo_setup_${DATE_TAG}.log"

# --- Kolory ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Domyslne wartosci ---
DRY_RUN=0
EXECUTE_MODE=0
SERVICE_BASE=""
ADMIN_CONN=""

# --- Funkcja usage ---
usage() {
    echo -e "${CYAN}==============================================================================${NC}"
    echo -e "${CYAN}   FSFO Setup Orchestrator (fsfo_setup.sh) v1.1${NC}"
    echo -e "${CYAN}==============================================================================${NC}"
    echo -e "Uzycie / Usage: $0 -s <service> [-d | -x] [-a <admin_conn>]"
    echo ""
    echo -e "${YELLOW}Wymagane / Required:${NC}"
    echo "  -s <service>    Nazwa serwisu PRIM (np. PRIM). Wola sqlconn.sh -s <service>"
    echo ""
    echo -e "${YELLOW}Opcjonalne / Optional:${NC}"
    echo "  -d              Dry-run: tylko wypisuje komendy dgmgrl do review (domyslne)"
    echo "  -x              Execute: po review, APLIKUJE dgmgrl script (wymaga -a)"
    echo "  -a <conn>       Admin connect string dla dgmgrl (np. sys/@PRIM_ADMIN)"
    echo "                  Wymagany z -x; wykorzystuje Oracle Wallet jesli @ bez hasla"
    echo ""
    echo -e "${YELLOW}Co robi / What it does:${NC}"
    echo "  1. Readiness check (sql/fsfo_check_readiness.sql)"
    echo "  2. Generator broker dgmgrl (sql/fsfo_configure_broker.sql) -> reports/"
    echo "  3. Review wskazowka dla DBA (manual review przed apply)"
    echo "  4. -x: aplikuje dgmgrl script (po review) + startuje observera (jesli lokalny)"
    echo ""
    echo -e "${YELLOW}Przyklady / Examples:${NC}"
    echo "  Dry-run:   $0 -s PRIM -d"
    echo "  Generator: $0 -s PRIM          # tylko generuje, nie aplikuje"
    echo "  Apply:     $0 -s PRIM -x -a 'sys/@PRIM_ADMIN'"
    echo -e "${CYAN}==============================================================================${NC}"
    exit 1
}

# --- Funkcja log ---
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

while getopts "s:dxa:" opt; do
    case ${opt} in
        s) SERVICE_BASE=$OPTARG ;;
        d) DRY_RUN=1 ;;
        x) EXECUTE_MODE=1 ;;
        a) ADMIN_CONN=$OPTARG ;;
        *) usage ;;
    esac
done

if [ -z "$SERVICE_BASE" ]; then
    echo -e "${RED}Blad: nie podano nazwy serwisu (-s)${NC}"
    usage
fi

if [ "$EXECUTE_MODE" -eq 1 ] && [ "$DRY_RUN" -eq 1 ]; then
    echo -e "${RED}Blad: -d i -x sa wzajemnie wykluczajace${NC}"
    usage
fi

if [ "$EXECUTE_MODE" -eq 1 ] && [ -z "$ADMIN_CONN" ]; then
    echo -e "${RED}Blad: tryb -x wymaga -a <admin_conn>${NC}"
    usage
fi

if [ "$EXECUTE_MODE" -eq 1 ] && ! command -v dgmgrl >/dev/null 2>&1; then
    echo -e "${RED}Blad: dgmgrl NIE w PATH (wymagany dla -x)${NC}"
    exit 2
fi

if ! command -v sqlconn.sh >/dev/null 2>&1; then
    log_msg "sqlconn.sh NIE znaleziony w PATH. Wymagany projekt 20260130-sqlconn w PATH." "ERROR"
    exit 2
fi

# --- Przygotowanie katalogow ---
mkdir -p "$LOG_DIR" "$REPORTS_DIR"

log_msg "FSFO Setup Orchestrator — start" "INFO"
log_msg "Service: $SERVICE_BASE | Dry-run: $DRY_RUN" "INFO"
log_msg "Log: $LOG_FILE" "INFO"

# ============================================================================
# KROK 1: Readiness check / STEP 1: Readiness check
# ============================================================================

log_msg "=== KROK 1: Readiness check ===" "INFO"
READINESS_REPORT="${REPORTS_DIR}/${SERVICE_BASE}_readiness_${DATE_TAG}.txt"
log_msg "Uruchamiam: sqlconn.sh -s $SERVICE_BASE -f sql/fsfo_check_readiness.sql" "INFO"

if [ "$DRY_RUN" -eq 1 ]; then
    log_msg "DRY-RUN: sqlconn.sh -s $SERVICE_BASE -f ${PROJECT_DIR}/sql/fsfo_check_readiness.sql -o $READINESS_REPORT" "WARN"
else
    sqlconn.sh -s "$SERVICE_BASE" \
               -f "${PROJECT_DIR}/sql/fsfo_check_readiness.sql" \
               -o "$READINESS_REPORT" \
        || { log_msg "Readiness check FAILED" "ERROR"; exit 3; }
    log_msg "Raport zapisany: $READINESS_REPORT" "OK"

    # Scan raport dla FAIL
    if grep -q "FAIL" "$READINESS_REPORT"; then
        log_msg "Readiness check: wykryto FAIL w raporcie! Przejrzyj $READINESS_REPORT" "WARN"
        log_msg "Kontynuacja pomimo FAIL — DBA musi ocenic ryzyko" "WARN"
    else
        log_msg "Readiness check: wszystko PASS" "OK"
    fi
fi

# ============================================================================
# KROK 2: Generator dgmgrl / STEP 2: dgmgrl generator
# ============================================================================

log_msg "=== KROK 2: Generator dgmgrl script ===" "INFO"
DGMGRL_SCRIPT="${REPORTS_DIR}/broker_setup_${SERVICE_BASE}_${DATE_TAG}.dgmgrl"
log_msg "Uruchamiam: sqlconn.sh -s $SERVICE_BASE -i -f sql/fsfo_configure_broker.sql" "INFO"

if [ "$DRY_RUN" -eq 1 ]; then
    log_msg "DRY-RUN: sqlconn.sh -s $SERVICE_BASE -i -f ${PROJECT_DIR}/sql/fsfo_configure_broker.sql -o $DGMGRL_SCRIPT" "WARN"
else
    sqlconn.sh -s "$SERVICE_BASE" \
               -i \
               -f "${PROJECT_DIR}/sql/fsfo_configure_broker.sql" \
               -o "$DGMGRL_SCRIPT" \
        || { log_msg "dgmgrl generator FAILED" "ERROR"; exit 4; }
    log_msg "dgmgrl skrypt wygenerowany: $DGMGRL_SCRIPT" "OK"
fi

# ============================================================================
# KROK 3: Review / Apply (zaleznie od trybu) / STEP 3: Review / Apply
# ============================================================================

if [ "$EXECUTE_MODE" -eq 0 ]; then
    log_msg "=== KROK 3: DBA review (tryb generator) ===" "INFO"
    echo ""
    echo -e "${YELLOW}==============================================================================${NC}"
    echo -e "${YELLOW} WAZNE: Review + manual apply${NC}"
    echo -e "${YELLOW}==============================================================================${NC}"
    echo ""
    echo "  Skrypt dgmgrl czeka na review DBA:"
    echo "     $DGMGRL_SCRIPT"
    echo ""
    echo "  Po review, wykonaj:"
    echo -e "     ${CYAN}$0 -s $SERVICE_BASE -x -a 'sys/@${SERVICE_BASE}_ADMIN'${NC}"
    echo ""
    echo "  Lub recznie:"
    echo -e "     ${CYAN}dgmgrl sys/@${SERVICE_BASE}_ADMIN @${DGMGRL_SCRIPT}${NC}"
    echo ""
    echo "  Nastepnie wdrozenie observerow - zob. FSFO-GUIDE.md sekcja 6."
    echo -e "${YELLOW}==============================================================================${NC}"

    log_msg "Orkiestrator zakonczony. Plik dgmgrl czeka na review: $DGMGRL_SCRIPT" "OK"
    exit 0
fi

# === TRYB EXECUTE (-x) ===
log_msg "=== KROK 3: APLIKACJA dgmgrl script ===" "INFO"

if [ ! -s "$DGMGRL_SCRIPT" ]; then
    log_msg "Skrypt dgmgrl pusty lub nie istnieje: $DGMGRL_SCRIPT" "ERROR"
    exit 5
fi

# Sprawdz czy broker juz jest enabled (idempotencja)
BROKER_STATE=$(dgmgrl -silent "$ADMIN_CONN" "SHOW CONFIGURATION" 2>/dev/null \
               | grep -iE "Configuration Status:" | head -1 || true)

if echo "$BROKER_STATE" | grep -qi "SUCCESS"; then
    log_msg "Configuration juz istnieje (SUCCESS). Sprawdz czy wymagana rekonfiguracja." "WARN"
    log_msg "Aby wymusic re-apply: najpierw REMOVE CONFIGURATION recznie." "WARN"
    exit 0
fi

# Log output dgmgrl do pliku
DGMGRL_OUT="${LOG_DIR}/dgmgrl_apply_${SERVICE_BASE}_${DATE_TAG}.log"
log_msg "Uruchamiam: dgmgrl <admin> @${DGMGRL_SCRIPT}" "INFO"
log_msg "Output: $DGMGRL_OUT" "INFO"

if dgmgrl -silent "$ADMIN_CONN" "@${DGMGRL_SCRIPT}" > "$DGMGRL_OUT" 2>&1; then
    log_msg "dgmgrl script zastosowany OK" "OK"
else
    log_msg "dgmgrl apply FAILED - sprawdz $DGMGRL_OUT" "ERROR"
    tail -20 "$DGMGRL_OUT" >&2
    exit 6
fi

# Weryfikacja koncowa
log_msg "Weryfikacja: SHOW FAST_START FAILOVER" "INFO"
dgmgrl -silent "$ADMIN_CONN" "SHOW FAST_START FAILOVER" | tee -a "$DGMGRL_OUT"

log_msg "KROK 3 zakonczony. Observer(y) musza byc uruchomione osobno przez systemd." "OK"
log_msg "Na kazdym hoscie observera: sudo systemctl start dgmgrl-observer-<site>" "INFO"

exit 0
