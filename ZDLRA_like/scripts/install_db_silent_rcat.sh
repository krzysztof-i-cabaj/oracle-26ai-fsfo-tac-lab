#!/bin/bash
# ==============================================================================
# Tytul:        install_db_silent_rcat.sh
# Opis:         Silent install Oracle Database 26ai 23.26.1 (Software Only) na rcat01.
#               Skopiowany z VMs2-install/scripts/install_db_silent.sh,
#               dostosowany dla Single Instance bez Oracle Restart.
# Description [EN]: Silent install Oracle DB 26ai 23.26.1 on rcat01 (SI without HAS).
#
# Autor:        KCB Kris
# Data:         2026-05-01
# Wersja:       1.0
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - Uruchamiac jako uzytkownik 'oracle'
#                    - Plik response (db_rcat_se2.rsp) podany jako argument
#                    - Mount /mnt/oracle_binaries z paczka 23.26.1 zip
# Requirements [EN]: - Run as 'oracle' user, response file as arg, /mnt/oracle_binaries mounted
#
# Uzycie [PL]:  bash install_db_silent_rcat.sh /tmp/scripts/db_rcat_se2.rsp
# Usage [EN]:   bash install_db_silent_rcat.sh <response_file_path>
# ==============================================================================

set -euo pipefail

log() { echo "[$(date +%H:%M:%S)] $*"; }

DB_HOME="/u01/app/oracle/product/23.26/dbhome_1"
DB_ZIP="/mnt/oracle_binaries/V1054592-01-OracleDatabase23.26.1.0.0forLinux_x86-64.zip"

if [ "$USER" != "oracle" ]; then
    echo "BLAD: Skrypt musi byc uruchomiony przez uzytkownika 'oracle'"
    echo "ERROR: Script must run as 'oracle' user"
    exit 1
fi

if [ -z "${1:-}" ]; then
    echo "Uzycie / Usage: bash install_db_silent_rcat.sh <response_file_path>"
    echo "Przyklad / Example: bash install_db_silent_rcat.sh /tmp/scripts/db_rcat_se2.rsp"
    exit 1
fi

RSP_FILE=$1

[ -f "$RSP_FILE" ] || { echo "BLAD: Response file $RSP_FILE nie istnieje"; exit 1; }
[ -f "$DB_ZIP" ]  || { echo "BLAD: Plik instalacyjny $DB_ZIP nie znaleziony. Sprawdz mount /mnt/oracle_binaries."; exit 1; }
[ -d "$DB_HOME" ] || { echo "BLAD: Katalog $DB_HOME nie istnieje. Kickstart powinien go utworzyc."; exit 1; }

log "=========================================================="
log " Oracle Database Software 26ai 23.26.1 - install for rcat01"
log "=========================================================="

log "1. Wypakowywanie binariow do $DB_HOME ..."
pushd "$DB_HOME" >/dev/null
unzip -q "$DB_ZIP"
popd >/dev/null
log "Wypakowywanie zakonczone."

log "2. Silent install (runInstaller)..."
export CV_ASSUME_DISTID=OEL8.10

set +e
"$DB_HOME/runInstaller" -silent -ignorePrereqFailure -responseFile "$RSP_FILE"
DB_RC=$?
set -e

if [ $DB_RC -ne 0 ]; then
    log "[FATAL] runInstaller exit code $DB_RC"
    log "Sprawdz logi w /u01/app/oraInventory/logs/"
    exit "$DB_RC"
fi

# 3. Utworz LISTENER przez netca silent.
# DBCA wymaga istniejacego listenera (parametr -listeners LISTENER w dbca_create_rcat.sh).
# Bez tego DBCA wyrzuca DBT-07505 'Selected listener (LISTENER) does not exist'.
# Default netca.rsp tworzy LISTENER na porcie 1521 + auto-start.
# Lesson learned 2026-05-03: ten krok byl pominiety w pierwotnej wersji skryptu, dolozony post-mortem.
# 3. Create LISTENER via netca silent. DBCA requires existing listener (-listeners LISTENER).
# Without it DBCA throws DBT-07505. Default netca.rsp creates LISTENER on port 1521.
# Lesson 2026-05-03: this step was missing in original script, added post-mortem.
log "3. Tworzenie LISTENER (netca silent)..."
NETCA_RSP="$DB_HOME/assistants/netca/netca.rsp"
[ -f "$NETCA_RSP" ] || { echo "BLAD: $NETCA_RSP nie istnieje (paczka 23ai uszkodzona?)"; exit 1; }

set +e
"$DB_HOME/bin/netca" -silent -responseFile "$NETCA_RSP"
NETCA_RC=$?
set -e

if [ $NETCA_RC -ne 0 ]; then
    log "[WARN] netca exit code $NETCA_RC - LISTENER moze juz istniec (sprawdz: lsnrctl status)"
else
    log "[OK] LISTENER utworzony na porcie 1521 i wystartowany."
fi

log "=========================================================="
log " Instalacja zainicjowana. Wykonaj jako root:"
log "   $DB_HOME/root.sh"
log "   (orainstRoot.sh - tylko jesli plik istnieje; przy pre-utworzonym oraInventory pomijany)"
log " Then run dbca_create_rcat.sh as oracle."
log "=========================================================="
