#!/bin/bash
# Skrypt: install_db_silent.sh | Script: install_db_silent.sh
# Cel: Automatyczna instalacja Oracle Database Software (Software Only) / Goal: Automatic installation of Oracle Database Software (Software Only)
# Wymaga przygotowanego pliku odpowiedzi (.rsp). Uruchamiać jako użytkownik 'oracle'. / Requires a prepared response file (.rsp). Run as 'oracle' user.

set -euo pipefail

log() { echo "[$(date +%H:%M:%S)] $*"; }

# Wersja / Version: 26ai (23.26.1)
DB_HOME="/u01/app/oracle/product/23.26/dbhome_1"
DB_ZIP="/mnt/oracle_binaries/V1054592-01-OracleDatabase23.26.1.0.0forLinux_x86-64.zip"

if [ "$USER" != "oracle" ]; then
    echo "BŁĄD: Skrypt musi być uruchomiony przez użytkownika 'oracle'! / ERROR: Script must be run by 'oracle' user!"
    exit 1
fi

if [ -z "$1" ]; then
    echo "Użycie: bash install_db_silent.sh <ścieżka_do_pliku_rsp> / Usage: bash install_db_silent.sh <path_to_rsp_file>"
    echo "Przykład: bash install_db_silent.sh /home/oracle/db.rsp / Example: bash install_db_silent.sh /home/oracle/db.rsp"
    exit 1
fi

RSP_FILE=$1

if [ ! -f "$RSP_FILE" ]; then
    echo "BŁĄD: Plik odpowiedzi $RSP_FILE nie istnieje! / ERROR: Response file $RSP_FILE does not exist!"
    exit 1
fi

if [ ! -f "$DB_ZIP" ]; then
    echo "BŁĄD: Plik instalacyjny Database $DB_ZIP nie został znaleziony. Sprawdź podmontowanie w /mnt/oracle_binaries. / ERROR: Database installation file $DB_ZIP not found. Check mounts in /mnt/oracle_binaries."
    exit 1
fi

log "=========================================================="
log "    Instalacja Oracle Database Software 26ai              "
log "    Oracle Database Software 26ai Installation            "
log "=========================================================="

log "1. Wypakowywanie binariów bezpośrednio do DB_HOME ($DB_HOME)... / 1. Unpacking binaries directly into DB_HOME ($DB_HOME)..."
# F-19: pushd/popd zamiast cd, by nie zmieniac globalnego CWD. / F-19: pushd/popd instead of cd to keep global CWD intact.
pushd "$DB_HOME" >/dev/null
unzip -q "$DB_ZIP"
popd >/dev/null
log "Wypakowywanie zakończone pomyślnie. / Unpacking completed successfully."

log "2. Uruchamianie cichej instalacji (runInstaller)... / 2. Starting silent installation (runInstaller)..."
export CV_ASSUME_DISTID=OEL8.10

# F-01: NIE ukrywamy bledow runInstaller. / F-01: Do NOT hide runInstaller errors.
set +e
"$DB_HOME/runInstaller" -silent -ignorePrereqFailure -responseFile "$RSP_FILE"
DB_RC=$?
set -e

if [ $DB_RC -ne 0 ]; then
    log "=========================================================="
    log "[FATAL] runInstaller zwrocil kod $DB_RC - instalacja przerwana."
    log "[FATAL] runInstaller exited with code $DB_RC - installation aborted."
    log "Sprawdz logi / Check logs:"
    log "  /u01/app/oraInventory/logs/installActions*.log"
    log "  /u01/app/oraInventory/logs/silentInstall*.log"
    log "=========================================================="
    exit "$DB_RC"
fi

log "=========================================================="
log " Instalacja zainicjowana. Otwórz terminal jako ROOT       "
log " i wykonaj wskazany skrypt root.sh na wszystkich węzłach. "
log " Installation initiated. Open a terminal as ROOT          "
log " and execute the indicated root.sh script on all nodes.   "
log "=========================================================="
