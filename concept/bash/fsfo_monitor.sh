#!/bin/bash
# ==============================================================================
# Tytul:        fsfo_monitor.sh
# Opis:         Cron-friendly health monitor dla FSFO + TAC.
#               Tryb -a (alert) zwraca exit code:
#                 0 = OK, 1 = WARNING, 2 = CRITICAL
# Description [EN]: Cron-friendly health monitor for FSFO + TAC.
#                   Alert mode (-a) returns exit codes:
#                     0 = OK, 1 = WARNING, 2 = CRITICAL
#
# Autor:        KCB Kris
# Data:         2026-04-23
# Wersja:       1.0
#
# Wymagania [PL]:    - sqlconn.sh w PATH
#                    - Uzywa sql/fsfo_monitor.sql (7 sekcji)
# Requirements [EN]: - sqlconn.sh in PATH
#                    - Uses sql/fsfo_monitor.sql (7 sections)
#
# Uzycie [PL]:       ./fsfo_monitor.sh -s PRIM [-a] [-o plik.txt]
# Usage [EN]:        ./fsfo_monitor.sh -s PRIM [-a] [-o file.txt]
# ==============================================================================

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

# Trap ERR - kontekst bledu dla cron/systemd (linia, funkcja, exit code)
trap 'rc=$?; echo "[$(date +%FT%T)] ERROR rc=$rc at ${BASH_SOURCE[0]}:${LINENO} in ${FUNCNAME[0]:-main}" >&2; exit $rc' ERR

# --- Konfiguracja ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( dirname "$SCRIPT_DIR" )"
LOG_DIR="${PROJECT_DIR}/logs"
REPORTS_DIR="${PROJECT_DIR}/reports"

DATE_TAG=$(date +%Y%m%d_%H%M%S)

# --- Kolory (tylko gdy terminal) ---
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi

# --- Domyslne wartosci ---
ALERT_MODE=0
SERVICE_BASE=""
OUTPUT_FILE=""

# --- Usage ---
usage() {
    cat <<EOF
==============================================================================
   FSFO Health Monitor (fsfo_monitor.sh) v1.0
==============================================================================
Uzycie / Usage: $0 -s <service> [-a] [-o plik]

Wymagane / Required:
  -s <service>    Nazwa serwisu (np. PRIM)

Opcjonalne / Optional:
  -a              Alert mode — exit 0/1/2 dla cron integration
  -o <plik>       Plik output (zamiast logow)

Exit codes (-a):
  0 = OK (wszystko zielone)
  1 = WARNING (apply lag 5-30s, observer reconnecting, service degraded)
  2 = CRITICAL (FSFO disabled, observer disconnected, apply lag > 30s)

Przyklad cron (co 5 min):
  */5 * * * * /path/to/fsfo_monitor.sh -s PRIM -a >> /var/log/fsfo_monitor.log 2>&1
==============================================================================
EOF
    exit 1
}

# --- Parsowanie argumentow ---
if [ $# -eq 0 ]; then usage; fi

while getopts "s:ao:" opt; do
    case ${opt} in
        s) SERVICE_BASE=$OPTARG ;;
        a) ALERT_MODE=1 ;;
        o) OUTPUT_FILE=$OPTARG ;;
        *) usage ;;
    esac
done

if [ -z "$SERVICE_BASE" ]; then
    echo "${RED}Blad: nie podano -s${NC}"
    usage
fi

if ! command -v sqlconn.sh >/dev/null 2>&1; then
    echo "${RED}[ERROR] sqlconn.sh NIE w PATH${NC}" >&2
    exit 2
fi

# --- Przygotowanie ---
mkdir -p "$LOG_DIR" "$REPORTS_DIR"

if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="${REPORTS_DIR}/${SERVICE_BASE}_fsfo_monitor_${DATE_TAG}.txt"
fi

# ============================================================================
# Uruchom monitor SQL
# ============================================================================

# Obsluga bledow sqlconn.sh: przy set -e nie-zerowy exit zabije skrypt.
# Dla monitora chcemy wylapac blad i zwrocic exit 2 (CRITICAL) zamiast cichego failure.
SQL_EXIT=0
sqlconn.sh -s "$SERVICE_BASE" \
           -f "${PROJECT_DIR}/sql/fsfo_monitor.sql" \
           -o "$OUTPUT_FILE" 2>>"${LOG_DIR}/fsfo_monitor_sqlconn_${DATE_TAG}.err" \
    || SQL_EXIT=$?

if [ "$SQL_EXIT" -ne 0 ]; then
    if [ "$ALERT_MODE" -eq 1 ]; then
        echo "[CRITICAL] sqlconn.sh failed for service $SERVICE_BASE (exit $SQL_EXIT)"
        exit 2
    else
        echo -e "${RED}[CRITICAL] sqlconn.sh failed (exit $SQL_EXIT)${NC}"
        echo "Stderr: ${LOG_DIR}/fsfo_monitor_sqlconn_${DATE_TAG}.err"
        exit 2
    fi
fi

# Sanity check: pusty plik = ukryty blad (np. sqlplus segfault)
if [ ! -s "$OUTPUT_FILE" ]; then
    if [ "$ALERT_MODE" -eq 1 ]; then
        echo "[CRITICAL] Output empty for service $SERVICE_BASE — sqlplus may have crashed"
        exit 2
    else
        echo -e "${RED}[CRITICAL] Output empty — health assessment skipped${NC}"
        exit 2
    fi
fi

# ============================================================================
# Analiza wynikow (dla alert mode)
# ============================================================================

if [ "$ALERT_MODE" -eq 0 ]; then
    # Normalny tryb — pokaz output i zakoncz
    if [ -t 1 ]; then
        cat "$OUTPUT_FILE"
    fi
    echo ""
    echo "${GREEN}Raport: $OUTPUT_FILE${NC}"
    exit 0
fi

# === ALERT MODE ===
# Parse output dla stanow krytycznych

SEVERITY=0   # 0=OK, 1=WARN, 2=CRIT
ALERTS=""

# CRIT: Observer NIE connected
if grep -E "Observer Present[[:space:]]+\|?[[:space:]]*NO" "$OUTPUT_FILE" >/dev/null 2>&1 || \
   grep -E "FS Failover Observer Present.*NO" "$OUTPUT_FILE" >/dev/null 2>&1; then
    ALERTS="${ALERTS}[CRIT] Observer disconnected\n"
    SEVERITY=2
fi

# CRIT: FSFO not SYNCHRONIZED
if grep -E "FS Failover Status.*NOT SYNCHRONIZED" "$OUTPUT_FILE" >/dev/null 2>&1; then
    ALERTS="${ALERTS}[CRIT] FSFO not SYNCHRONIZED\n"
    SEVERITY=2
fi

# CRIT: apply lag >= 30s (LagLimit)
if grep -E "apply lag.*CRIT" "$OUTPUT_FILE" >/dev/null 2>&1; then
    ALERTS="${ALERTS}[CRIT] Apply lag exceeds FastStartFailoverLagLimit (30s)\n"
    SEVERITY=2
fi

# WARN: apply lag 5-30s
if grep -E "apply lag.*WARN" "$OUTPUT_FILE" >/dev/null 2>&1; then
    ALERTS="${ALERTS}[WARN] Apply lag 5-30s\n"
    if [ "$SEVERITY" -lt 1 ]; then SEVERITY=1; fi
fi

# CRIT: TAC success rate < 80%
if grep -E "requests_failed.*CRIT" "$OUTPUT_FILE" >/dev/null 2>&1; then
    ALERTS="${ALERTS}[CRIT] TAC replay success rate < 80%\n"
    SEVERITY=2
fi

# WARN: TAC success rate 80-95%
if grep -E "requests.*WARN" "$OUTPUT_FILE" >/dev/null 2>&1; then
    ALERTS="${ALERTS}[WARN] TAC replay success rate 80-95%\n"
    if [ "$SEVERITY" -lt 1 ]; then SEVERITY=1; fi
fi

# CRIT: Archive gap LARGE
if grep -E "gap_size[[:space:]]+.*[1-9][0-9]+" "$OUTPUT_FILE" >/dev/null 2>&1; then
    ALERTS="${ALERTS}[CRIT] Archive log gap detected\n"
    SEVERITY=2
fi

# Emit result
case $SEVERITY in
    0)
        echo "[OK] FSFO+TAC healthy (service=$SERVICE_BASE, report=$OUTPUT_FILE)"
        exit 0
        ;;
    1)
        echo "[WARNING] FSFO+TAC degraded (service=$SERVICE_BASE)"
        echo -e "$ALERTS"
        echo "Report: $OUTPUT_FILE"
        exit 1
        ;;
    2)
        echo "[CRITICAL] FSFO+TAC ALERT (service=$SERVICE_BASE)"
        echo -e "$ALERTS"
        echo "Report: $OUTPUT_FILE"
        exit 2
        ;;
esac
