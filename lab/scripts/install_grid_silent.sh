#!/bin/bash
# Skrypt: install_grid_silent.sh | Script: install_grid_silent.sh
# Cel: Automatyczna instalacja Oracle Grid Infrastructure (wypakowanie i uruchomienie gridSetup.sh) / Goal: Automatic installation of Oracle Grid Infrastructure (unpack and run gridSetup.sh)
# Wymaga przygotowanego pliku odpowiedzi (.rsp). Uruchamiać jako użytkownik 'grid'. / Requires a prepared response file (.rsp). Run as 'grid' user.

set -euo pipefail

log() { echo "[$(date +%H:%M:%S)] $*"; }

# Wersja / Version: 26ai (23.26.1)
GRID_HOME="/u01/app/23.26/grid"
GRID_ZIP="/mnt/oracle_binaries/V1054596-01-OracleDatabaseGridInfrastructure23.26.1.0.0forLinux_x86-64.zip"

if [ "$USER" != "grid" ]; then
    echo "BŁĄD: Skrypt musi być uruchomiony przez użytkownika 'grid'! / ERROR: Script must be run by 'grid' user!"
    exit 1
fi

if [ -z "$1" ]; then
    echo "Użycie: bash install_grid_silent.sh <ścieżka_do_pliku_rsp> / Usage: bash install_grid_silent.sh <path_to_rsp_file>"
    echo "Przykład: bash install_grid_silent.sh /home/grid/grid_rac.rsp / Example: bash install_grid_silent.sh /home/grid/grid_rac.rsp"
    exit 1
fi

RSP_FILE=$1

if [ ! -f "$RSP_FILE" ]; then
    echo "BŁĄD: Plik odpowiedzi $RSP_FILE nie istnieje! / ERROR: Response file $RSP_FILE does not exist!"
    exit 1
fi

if [ ! -f "$GRID_ZIP" ]; then
    echo "BŁĄD: Plik instalacyjny Grid $GRID_ZIP nie został znaleziony. Sprawdź podmontowanie w /mnt/oracle_binaries. / ERROR: Grid installation file $GRID_ZIP not found. Check mounts in /mnt/oracle_binaries."
    exit 1
fi

log "=========================================================="
log "    Instalacja Oracle Grid Infrastructure 26ai            "
log "    Oracle Grid Infrastructure 26ai Installation          "
log "=========================================================="

log "1. Wypakowywanie binariów bezpośrednio do GRID_HOME ($GRID_HOME)... / 1. Unpacking binaries directly into GRID_HOME ($GRID_HOME)..."
# Oracle 23ai+ wymaga "Image Install" (rozpakowanie ZIP-a bezposrednio w $ORACLE_HOME) / Oracle 23ai+ requires "Image Install" (unpacking ZIP directly in $ORACLE_HOME)
pushd "$GRID_HOME" >/dev/null
unzip -o -q "$GRID_ZIP"
popd >/dev/null
log "Wypakowywanie zakończone pomyślnie. / Unpacking completed successfully."

log "2. Uruchamianie cichej instalacji (gridSetup.sh)... / 2. Starting silent installation (gridSetup.sh)..."
# -ignorePrereqFailure jest wymagany, z uwagi na minimalne braki np. w dostepnej pamięci operacyjnej (cluvfy strict checks). / -ignorePrereqFailure is required, due to minor shortages e.g. in available RAM (cluvfy strict checks).
export CV_ASSUME_DISTID=OEL8.10

# F-01: NIE ukrywamy bledow gridSetup. INS-10105 / PRVG-* / PRCT-* maja przerwac pipeline. / F-01: Do NOT hide gridSetup errors.
set +e
"$GRID_HOME/gridSetup.sh" -silent -ignorePrereqFailure -responseFile "$RSP_FILE"
GRID_RC=$?
set -e

if [ $GRID_RC -ne 0 ]; then
    log "=========================================================="
    log "[FATAL] gridSetup.sh zwrocil kod $GRID_RC - instalacja przerwana."
    log "[FATAL] gridSetup.sh exited with code $GRID_RC - installation aborted."
    log "Sprawdz logi / Check logs:"
    log "  /u01/app/oraInventory/logs/installActions*.log"
    log "  /u01/app/oraInventory/logs/silentInstall*.log"
    log "=========================================================="
    exit "$GRID_RC"
fi

log "=========================================================="
log " Instalacja zainicjowana. Otwórz nowy terminal jako ROOT  "
log " i wykonaj skrypty root.sh na tym węźle:                  "
log "   /u01/app/oraInventory/orainstRoot.sh                   "
log "   /u01/app/23.26/grid/root.sh                            "
log " RAC: najpierw prim01, potem prim02 (sekwencyjnie!).      "
log " Oracle Restart (stby01): tylko lokalnie, brak executeConfigTools."
log " Installation initiated. Open a new terminal as ROOT      "
log " and run root.sh scripts on this node:                    "
log "   /u01/app/oraInventory/orainstRoot.sh                   "
log "   /u01/app/23.26/grid/root.sh                            "
log " RAC: prim01 first, then prim02 (sequentially!).          "
log " Oracle Restart (stby01): local only, no executeConfigTools."
log "=========================================================="
