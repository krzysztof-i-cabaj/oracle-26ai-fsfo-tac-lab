#!/bin/bash
# ==============================================================================
# Tytul:        validate_all.sh
# Opis:         Pelna walidacja FSFO+TAC na wielu bazach z listy targets.
#               Wzorzec z ../20260130-sqlconn/sqlmulti.sh - generuje raport zbiorczy.
# Description [EN]: Full FSFO+TAC validation across multiple databases from targets list.
#                   Based on ../20260130-sqlconn/sqlmulti.sh pattern - generates consolidated report.
#
# Autor:        KCB Kris
# Data:         2026-04-23
# Wersja:       1.0
#
# Wymagania [PL]:    - sqlconn.sh w PATH
#                    - Plik targets z lista baz (jedna w linii, # = komentarz)
# Requirements [EN]: - sqlconn.sh in PATH
#                    - Targets file with DB names (one per line, # = comment)
#
# Uzycie [PL]:       ./validate_all.sh -l targets.lst [-d]
# Usage [EN]:        ./validate_all.sh -l targets.lst [-d]
# ==============================================================================

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

# Trap ERR - kontekst bledu (linia, funkcja, exit code)
trap 'rc=$?; echo "[$(date +%FT%T)] ERROR rc=$rc at ${BASH_SOURCE[0]}:${LINENO} in ${FUNCNAME[0]:-main}" >&2; exit $rc' ERR

# --- Konfiguracja ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( dirname "$SCRIPT_DIR" )"
LOG_DIR="${PROJECT_DIR}/logs"
REPORTS_DIR="${PROJECT_DIR}/reports"
SQL_SCRIPT="${PROJECT_DIR}/sql/validate_environment.sql"

DATE_TAG=$(date +%Y%m%d_%H%M)
MASTER_REPORT="${REPORTS_DIR}/FULL_VALIDATION_${DATE_TAG}.txt"
LOG_FILE="${LOG_DIR}/validate_all_${DATE_TAG}.log"

# --- Kolory ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Domyslne ---
TARGET_LIST=""
DRY_RUN=0

FAIL_COUNT=0
SUCCESS_COUNT=0
WARN_COUNT=0

usage() {
    cat <<EOF
==============================================================================
   Multi-DB Validation (validate_all.sh) v1.0
==============================================================================
Uzycie / Usage: $0 -l <targets_file> [-d]

Wymagane / Required:
  -l <file>    Plik z lista baz (np. targets.lst)

Opcjonalne / Optional:
  -d           Dry-run: tylko wypisuje co bedzie zrobione

Format pliku targets (jedna baza w linii, # = komentarz):
  # Produkcja
  PRIM
  STBY
  # CRM_PROD  <-- zakomentowana, zostanie pominieta

Output:
  reports/FULL_VALIDATION_<timestamp>.txt  — raport zbiorczy
  reports/<db>_validation_<timestamp>.txt  — raporty czastkowe
==============================================================================
EOF
    exit 1
}

# --- Parsing ---
if [ $# -eq 0 ]; then usage; fi

while getopts "l:d" opt; do
    case ${opt} in
        l) TARGET_LIST=$OPTARG ;;
        d) DRY_RUN=1 ;;
        *) usage ;;
    esac
done

if [ -z "$TARGET_LIST" ]; then
    echo -e "${RED}Blad: nie podano -l${NC}"
    usage
fi

if [ ! -f "$TARGET_LIST" ]; then
    echo -e "${RED}Blad: plik $TARGET_LIST nie istnieje${NC}"
    exit 2
fi

if ! command -v sqlconn.sh >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] sqlconn.sh NIE w PATH${NC}"
    exit 3
fi

mkdir -p "$LOG_DIR" "$REPORTS_DIR"

# ============================================================================
# Start master report
# ============================================================================

{
    echo "=================================================================="
    echo " FSFO + TAC MULTI-DB VALIDATION REPORT"
    echo " Run date: $(date)"
    echo " Target list: $TARGET_LIST"
    echo " SQL script: $SQL_SCRIPT"
    echo "=================================================================="
    echo ""
} > "$MASTER_REPORT"

echo -e "${CYAN}Rozpoczynam validate_all dla listy: $TARGET_LIST${NC}"
echo "Master report: $MASTER_REPORT" | tee -a "$LOG_FILE"
echo ""

# ============================================================================
# Iteracja po bazach
# ============================================================================

while IFS= read -r DB_SERVICE || [ -n "$DB_SERVICE" ]; do
    # Trim whitespace
    DB_SERVICE=$(echo "$DB_SERVICE" | xargs)

    # Skip empty and comments
    if [[ -z "$DB_SERVICE" ]] || [[ "$DB_SERVICE" == \#* ]]; then
        continue
    fi

    echo -ne "${CYAN}Validate: ${DB_SERVICE} ... ${NC}"

    SINGLE_REPORT="${REPORTS_DIR}/${DB_SERVICE}_validation_${DATE_TAG}.txt"

    if [ "$DRY_RUN" -eq 1 ]; then
        echo -e "${YELLOW}[DRY-RUN]${NC}"
        echo "  Wywolanie: sqlconn.sh -s $DB_SERVICE -f $SQL_SCRIPT -o $SINGLE_REPORT"
        continue
    fi

    # Wywolanie sqlconn.sh z obsluga bledow (set -e zabilby skrypt)
    EXIT_CODE=0
    sqlconn.sh -s "$DB_SERVICE" \
               -f "$SQL_SCRIPT" \
               -o "$SINGLE_REPORT" 2>>"$LOG_FILE" \
        || EXIT_CODE=$?

    if [ "$EXIT_CODE" -eq 0 ] && [ -s "$SINGLE_REPORT" ]; then
        # Parse report dla PASS/WARN/FAIL (|| true bo grep -c = 1 gdy brak match)
        FAIL_IN_DB=$(grep -c "FAIL" "$SINGLE_REPORT" 2>/dev/null || echo 0)
        WARN_IN_DB=$(grep -c "WARN" "$SINGLE_REPORT" 2>/dev/null || echo 0)

        if [ "$FAIL_IN_DB" -gt 0 ]; then
            echo -e "${RED}[FAIL]${NC} ($FAIL_IN_DB failures)"
            ((FAIL_COUNT++)) || true
        elif [ "$WARN_IN_DB" -gt 0 ]; then
            echo -e "${YELLOW}[WARN]${NC} ($WARN_IN_DB warnings)"
            ((WARN_COUNT++)) || true
        else
            echo -e "${GREEN}[OK]${NC}"
            ((SUCCESS_COUNT++)) || true
        fi

        # Dokleic do master raportu
        {
            echo ""
            echo "=================================================================="
            echo "  DB: $DB_SERVICE"
            echo "=================================================================="
            cat "$SINGLE_REPORT"
            echo ""
        } >> "$MASTER_REPORT"
    else
        echo -e "${RED}[ERROR]${NC} (sqlconn exit $EXIT_CODE)"
        ((FAIL_COUNT++)) || true

        {
            echo ""
            echo "=================================================================="
            echo "  DB: $DB_SERVICE — BLAD POLACZENIA (sqlconn exit $EXIT_CODE)"
            echo "=================================================================="
            echo ""
        } >> "$MASTER_REPORT"
    fi
done < "$TARGET_LIST"

# ============================================================================
# Podsumowanie
# ============================================================================

echo ""
echo "==================================================="
echo -e " ${CYAN}PODSUMOWANIE / SUMMARY${NC}"
echo "==================================================="
echo -e " Sukcesy / Success:  ${GREEN}$SUCCESS_COUNT${NC}"
echo -e " Ostrzezenia / Warn: ${YELLOW}$WARN_COUNT${NC}"
echo -e " Bledy / Errors:     ${RED}$FAIL_COUNT${NC}"
echo ""
echo " Master report: $MASTER_REPORT"
echo "==================================================="

# Tail master raportu z podsumowaniem
{
    echo ""
    echo "=================================================================="
    echo " SUMMARY"
    echo "=================================================================="
    echo " Success: $SUCCESS_COUNT"
    echo " Warnings: $WARN_COUNT"
    echo " Errors: $FAIL_COUNT"
    echo " End: $(date)"
    echo "=================================================================="
} >> "$MASTER_REPORT"

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 2
elif [ "$WARN_COUNT" -gt 0 ]; then
    exit 1
else
    exit 0
fi
