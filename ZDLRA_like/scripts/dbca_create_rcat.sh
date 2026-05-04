#!/bin/bash
# ==============================================================================
# Tytul:        dbca_create_rcat.sh
# Opis:         Tworzy CDB RCAT + PDB RCATPDB na rcat01 przez DBCA silent.
#               Uruchamiac jako oracle. Po install_db_silent_rcat.sh +
#               root.sh + orainstRoot.sh.
# Description [EN]: Creates CDB RCAT + PDB RCATPDB on rcat01 via DBCA silent.
#
# Autor:        KCB Kris
# Data:         2026-05-04 (v1.1: + post-DBCA ALTER USER SYS/SYSTEM, lesson #27)
#               (v1.0: initial DBCA silent install)
# Wersja:       1.1
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - Uruchamiac jako oracle
#                    - install_db_silent_rcat.sh wykonany + root scripts
#                    - ORACLE_HOME, ORACLE_SID w .bash_profile
# Requirements [EN]: - Run as oracle, after DB software install + root scripts.
#
# Uzycie [PL]:  bash dbca_create_rcat.sh
# Usage [EN]:   bash dbca_create_rcat.sh
# ==============================================================================

set -euo pipefail

# --- LAB secrets (konwencja VMs2-install) ---
# Source haslo zunifikowane LAB z /root/.lab_secrets (lub $HOME/.lab_secrets).
# Plik tworzony przez kickstart (ks-rcat01.cfg) z chmod 600.
[ -r /root/.lab_secrets ] && source /root/.lab_secrets
[ -r "$HOME/.lab_secrets" ] && source "$HOME/.lab_secrets"
if [ -z "${LAB_PASS:-}" ]; then
    echo "BLAD: LAB_PASS nieustawiona. Stworz /root/.lab_secrets z 'export LAB_PASS=...' (chmod 600)."
    echo "ERROR: LAB_PASS not set. Create /root/.lab_secrets with 'export LAB_PASS=...' (chmod 600)."
    exit 1
fi

log() { echo "[$(date +%H:%M:%S)] $*"; }

[ "$USER" = "oracle" ] || { echo "BLAD: Uruchom jako oracle."; exit 1; }
[ "$(hostname -s)" = "rcat01" ] || { echo "BLAD: Skrypt dla rcat01."; exit 1; }

ORACLE_HOME="/u01/app/oracle/product/23.26/dbhome_1"
ORACLE_BASE="/u01/app/oracle"
SID="RCAT"
PDB_NAME="RCATPDB"
CHAR_SET="AL32UTF8"

# Haslo zunifikowane LAB
SYS_PWD="${LAB_PASS}"
SYSTEM_PWD="${LAB_PASS}"
PDBADMIN_PWD="${LAB_PASS}"

# SGA dla 4 GB RAM (1024 hugepages * 2 MB = 2 GB)
SGA_TARGET_MB=1536
PGA_AGGREGATE_MB=512

log "=== DBCA: Creating CDB $SID + PDB $PDB_NAME on rcat01 ==="

export ORACLE_HOME ORACLE_BASE ORACLE_SID="$SID"
export PATH="$ORACLE_HOME/bin:$PATH"

# Idempotencja: jesli baza juz istnieje, konczymy
if [ -f "$ORACLE_HOME/dbs/spfile${SID}.ora" ] || [ -f "$ORACLE_HOME/dbs/init${SID}.ora" ]; then
    log "[skip] Baza $SID juz istnieje (spfile/init found). Aby przebudowac: dbca -deleteDatabase -sid $SID"
    exit 0
fi

# Wywolanie DBCA
log "Uruchamiam DBCA silent (this can take 10-20 min)..."

dbca -silent -createDatabase \
    -templateName General_Purpose.dbc \
    -gdbName "$SID" \
    -sid "$SID" \
    -responseFile NO_VALUE \
    -characterSet "$CHAR_SET" \
    -nationalCharacterSet AL16UTF16 \
    -sysPassword "$SYS_PWD" \
    -systemPassword "$SYSTEM_PWD" \
    -createAsContainerDatabase true \
    -numberOfPDBs 1 \
    -pdbName "$PDB_NAME" \
    -pdbAdminPassword "$PDBADMIN_PWD" \
    -databaseType MULTIPURPOSE \
    -automaticMemoryManagement false \
    -totalMemory "$SGA_TARGET_MB" \
    -storageType FS \
    -datafileDestination "/u02/oradata" \
    -recoveryAreaDestination "/u03/fra" \
    -recoveryAreaSize 30000 \
    -enableArchive true \
    -archiveLogMode true \
    -listeners LISTENER \
    -emConfiguration NONE \
    -redoLogFileSize 200

# Po DBCA dopisanie do /etc/oratab z flaga Y (auto-start dla dbstart).
# UWAGA: Bez sudo - oratab ma chmod 664 root:oinstall (Oracle convention),
# user oracle (czlonek oinstall) edytuje bezposrednio.
# Wymaga uprzedniego setup_oracle_env_rcat.sh (lub kickstart) ktory ustawi uprawnienia.
# Lesson learned 2026-05-03: bez tego sudo wisi na hasle, script wyrzuca timeout.
# IMPORTANT: No sudo needed - oratab is chmod 664 root:oinstall (Oracle convention),
# oracle user (oinstall member) edits directly. Requires setup_oracle_env_rcat.sh first.
log "Aktualizacja /etc/oratab (flaga Y dla auto-start, bez sudo - oinstall writable)..."
if [ ! -w /etc/oratab ]; then
    echo "BLAD: /etc/oratab nie jest writable dla oracle. Uruchom najpierw setup_oracle_env_rcat.sh"
    echo "ERROR: /etc/oratab not writable by oracle. Run setup_oracle_env_rcat.sh first."
    exit 1
fi
if grep -q "^${SID}:" /etc/oratab; then
    sed -i "s|^${SID}:.*|${SID}:${ORACLE_HOME}:Y|" /etc/oratab
else
    echo "${SID}:${ORACLE_HOME}:Y" >> /etc/oratab
fi
log "[OK] /etc/oratab: ${SID}:${ORACLE_HOME}:Y"

# Lesson #27 (iter.14, 2026-05-04): mimo ze DBCA dostaje -sysPassword, empirycznie
# password file na rcat01 nie jest zsynchronizowane z LAB_PASS. Bez tego sync:
# - rman_cat connection from PRIM (catalog) wymaga password file auth -> ORA-01017
# - LOG_ARCHIVE_DEST_3 (real-time redo do rcat_redo) -> ORA-16191 'unable to log'
# - Inne password-file-auth functionalities (DG, RAC sync z PRIM) tez sie nie sprawdzaja
# Fix: explicit ALTER USER SYS/SYSTEM po DBCA, OS authentication bypass-uje.
# Verify: lokalny TCP login musi przejsc bez ORA-01017.
log "Lesson #27 fix: synchronizacja SYS/SYSTEM password z LAB_PASS (post-DBCA)..."
sqlplus -S / as sysdba <<EOF
ALTER USER SYS IDENTIFIED BY "${LAB_PASS}";
ALTER USER SYSTEM IDENTIFIED BY "${LAB_PASS}";
EXIT
EOF

log "Verify: lokalny TCP login jako sys (powinno przejsc bez ORA-01017)..."
sqlplus -L "sys/${LAB_PASS}@localhost:1521/${SID} as sysdba" <<EOF
SELECT 'SYS LOGIN OK: ' || instance_name FROM v\$instance;
EXIT
EOF
[ $? -eq 0 ] || { echo "BLAD: SYS login fail po ALTER USER. Sprawdz hasło / PASSWORD FILE."; exit 1; }

# Walidacja
log "Walidacja: status instancji"
sqlplus -S / as sysdba <<EOF
SET HEADING OFF FEEDBACK OFF
SELECT 'INSTANCE: ' || instance_name || ' STATUS: ' || status FROM v\$instance;
SELECT 'PDB: ' || name || ' OPEN: ' || open_mode FROM v\$pdbs;
SELECT 'ARCHIVELOG: ' || log_mode FROM v\$database;
EXIT
EOF

log "=== CDB $SID + PDB $PDB_NAME created successfully ==="
log "Nastepne kroki / Next steps:"
log "  1. setup_systemd_oracle_unit.sh (auto-start po reboocie)"
log "  2. catalog_create.sh (schemat katalogu RMAN)"
log "  3. catalog_register_prim.sh (rejestracja PRIM)"
