#!/usr/bin/env bash
# ==============================================================================
# Tytul:        tac_service_resume.sh
# Opis:         Wznawia serwis aplikacyjny MYAPP_TAC na lokalnej instancji
#               po unplanned failover lub switchover. Niezbedne na stby01
#               (Single Instance + Oracle Restart, bez GI Cluster CRS auto-start).
#               Skrypt sprawdza role bazy, sprawdza czy serwis jest aktywny w PDB,
#               i jesli nie - wykonuje DBMS_SERVICE.START_SERVICE('myapp_tac').
# Description [EN]: Resume MYAPP_TAC service on the local instance after a
#               failover/switchover. Required on stby01 (SI Restart - no Grid
#               CRS auto-start). Idempotent and safe to re-run.
#
# Autor:        KCB Kris
# Data:         2026-04-27
# Wersja:       1.0 (VMs2-install) - F-13/post-failover gap (analog FIX-095 z VMs).
#
# Wymagania [PL]:    - Uruchamiac jako oracle na bazie, ktora wlasnie zostala primary.
#                    - $ORACLE_HOME, $ORACLE_SID ustawione w .bash_profile.
# Requirements [EN]: - Run as oracle on the freshly-promoted primary; ORACLE_HOME/SID set.
#
# Uzycie [PL]:
#   ssh oracle@stby01 'bash <repo>/scripts/tac_service_resume.sh'
#   # albo z parametrem nazwy serwisu/PDB:
#   SERVICE_NAME=myapp_tac PDB_NAME=APPPDB bash tac_service_resume.sh
# Usage [EN]: see above.
# ==============================================================================

set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-myapp_tac}"
PDB_NAME="${PDB_NAME:-APPPDB}"

if [ -z "${ORACLE_HOME:-}" ] || [ -z "${ORACLE_SID:-}" ]; then
    echo "BŁĄD: ORACLE_HOME / ORACLE_SID nieustawione. / ERROR: ORACLE_HOME/SID not set."
    echo "Uruchom: . ~/.bash_profile && bash $0"
    exit 1
fi

echo "=========================================================="
echo "  TAC service resume — service=${SERVICE_NAME} pdb=${PDB_NAME}"
echo "  ORACLE_SID=${ORACLE_SID}  HOST=$(hostname -s)"
echo "=========================================================="

# 1. Sprawdz role bazy - musi byc PRIMARY by serwis dzialal.
ROLE=$(sqlplus -s / as sysdba <<'SQLEOF' | tr -d ' \t'
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF VERIFY OFF
SELECT database_role FROM v$database;
EXIT
SQLEOF
)

if [ "$ROLE" != "PRIMARY" ]; then
    echo "[INFO] Baza ma role '${ROLE}' (nie PRIMARY) — serwis aplikacyjny niepotrzebny."
    echo "[INFO] Database role is ${ROLE} (not PRIMARY) — service start skipped."
    exit 0
fi

# 2. Czy serwis jest juz aktywny w PDB?
ACTIVE=$(sqlplus -s / as sysdba <<SQLEOF | tr -d ' \t'
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF VERIFY OFF
ALTER SESSION SET CONTAINER=${PDB_NAME};
SELECT COUNT(*) FROM v\$active_services WHERE LOWER(name) = LOWER('${SERVICE_NAME}');
EXIT
SQLEOF
)

if [ "$ACTIVE" -ge 1 ]; then
    echo "[OK] Serwis ${SERVICE_NAME} jest juz aktywny w ${PDB_NAME}. / Service already active."
    exit 0
fi

# 3. Start serwisu.
echo "[INFO] Serwis ${SERVICE_NAME} nieaktywny — wykonuje DBMS_SERVICE.START_SERVICE..."
echo "[INFO] Service inactive — invoking DBMS_SERVICE.START_SERVICE..."

# Pulapki nazwy:
#   'MYAPP_TAC'             -> ORA-44773 (case mismatch)
#   'myapp_tac.lab.local'   -> ORA-44304 (z domain w CDB nie istnieje)
#   'myapp_tac'             -> OK
sqlplus -s / as sysdba <<SQLEOF
ALTER SESSION SET CONTAINER=${PDB_NAME};
BEGIN
    DBMS_SERVICE.START_SERVICE('${SERVICE_NAME}');
END;
/
EXIT
SQLEOF

# 4. Weryfikacja.
sleep 2
ACTIVE2=$(sqlplus -s / as sysdba <<SQLEOF | tr -d ' \t'
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF VERIFY OFF
ALTER SESSION SET CONTAINER=${PDB_NAME};
SELECT COUNT(*) FROM v\$active_services WHERE LOWER(name) = LOWER('${SERVICE_NAME}');
EXIT
SQLEOF
)

if [ "$ACTIVE2" -ge 1 ]; then
    echo "[OK] Serwis ${SERVICE_NAME} aktywny — TAC replay moze sie odbywac. / Service active — TAC ready."
else
    echo "[FAIL] Serwis nie wystartowal. / Service did not start."
    exit 1
fi
