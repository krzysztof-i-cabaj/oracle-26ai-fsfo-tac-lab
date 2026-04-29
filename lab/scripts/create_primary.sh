#!/bin/bash
# Skrypt: create_primary.sh | Script: create_primary.sh
# Cel: Automatyczne utworzenie bazy Primary przez DBCA i uruchomienie kluczowych funkcji (ArchiveLog, Flashback). / Goal: Automatically create Primary database via DBCA and start key features (ArchiveLog, Flashback).
# Uruchamiać jako użytkownik 'oracle' na węźle prim01. / Run as 'oracle' user on prim01 node.

set -e

log() { echo "[$(date +%H:%M:%S)] $*"; }

DB_HOME="/u01/app/oracle/product/23.26/dbhome_1"

if [ "$USER" != "oracle" ]; then
    echo "BŁĄD: Skrypt musi być uruchomiony przez użytkownika 'oracle'! / ERROR: Script must be run by 'oracle' user!"
    exit 1
fi

if [ -z "$1" ]; then
    echo "Użycie: bash create_primary.sh <ścieżka_do_pliku_dbca_rsp> / Usage: bash create_primary.sh <path_to_dbca_rsp_file>"
    echo "Przykład: bash create_primary.sh /home/oracle/dbca_prim.rsp / Example: bash create_primary.sh /home/oracle/dbca_prim.rsp"
    exit 1
fi

RSP_FILE=$1

if [ ! -f "$RSP_FILE" ]; then
    echo "BŁĄD: Plik odpowiedzi $RSP_FILE nie istnieje! / ERROR: Response file $RSP_FILE does not exist!"
    exit 1
fi

log "=========================================================="
log "    Tworzenie Głównej Bazy (Primary) z użyciem DBCA       "
log "    Creating Primary Database using DBCA                  "
log "=========================================================="

log "1. Uruchamianie DBCA (proces potrwa ok. 30-50 minut)... / 1. Running DBCA (process takes approx. 30-50 minutes)..."
$DB_HOME/bin/dbca -silent -createDatabase -responseFile $RSP_FILE || true

log "2. Konfiguracja po instalacji (ARCHIVELOG, FORCE LOGGING, FLASHBACK) / 2. Post-installation config (ARCHIVELOG, FORCE LOGGING, FLASHBACK)"
# DBCA z szablonem New_Database.dbt tworzy baze w trybie NOARCHIVELOG. / DBCA with New_Database.dbt template creates DB in NOARCHIVELOG mode.
# Archivelog i Flashback są absolutnie wymagane dla FSFO i bazy Standby. / Archivelog and Flashback are absolutely required for FSFO and Standby database.

export ORACLE_SID=PRIM1
export ORACLE_HOME=$DB_HOME
export PATH=$ORACLE_HOME/bin:$PATH

log "Przełączanie bazy w tryb ARCHIVELOG i FLASHBACK ON... / Switching database to ARCHIVELOG and FLASHBACK ON mode..."

srvctl stop database -d PRIM
srvctl start database -d PRIM -startoption mount

sqlplus / as sysdba <<EOF
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE FORCE LOGGING;
ALTER DATABASE FLASHBACK ON;
ALTER DATABASE OPEN;
EXIT;
EOF

# Weryfikacja / Verification
sqlplus -s / as sysdba <<EOF
set linesize 200
col log_mode format a15
col flashback_on format a15
col force_logging format a15
SELECT log_mode, flashback_on, force_logging FROM v\$database;
EXIT;
EOF

log "=========================================================="
log "    Baza PRIM została pomyślnie utworzona i skonfigurowana"
log "    PRIM database was successfully created and configured "
log "=========================================================="
