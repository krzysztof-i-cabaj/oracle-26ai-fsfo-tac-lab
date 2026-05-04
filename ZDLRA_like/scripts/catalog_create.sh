#!/bin/bash
# ==============================================================================
# Tytul:        catalog_create.sh
# Opis:         Tworzy schemat rman_cat + CREATE CATALOG w PDB RCATPDB na rcat01.
#               Wywoluje sql/01_create_catalog_schema.sql i sql/02_create_catalog.sql.
# Description [EN]: Creates rman_cat schema + RMAN catalog in PDB RCATPDB on rcat01.
#
# Autor:        KCB Kris
# Data:         2026-05-01
# Wersja:       1.0
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - Uruchamiac NA rcat01 jako oracle
#                    - DB RCAT + PDB RCATPDB OPEN
#                    - Listener zarejestrowal RCATPDB (lsnrctl status)
# Requirements [EN]: - Run on rcat01 as oracle, RCATPDB open, registered with listener.
#
# Uzycie [PL]:  bash catalog_create.sh
# Usage [EN]:   bash catalog_create.sh
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="$SCRIPT_DIR/../sql"
PDB_TNS="rcat01:1521/RCATPDB"
RCAT_PWD="${LAB_PASS}"

[ -f "$SQL_DIR/01_create_catalog_schema.sql" ] || { echo "BLAD: $SQL_DIR/01_create_catalog_schema.sql nie istnieje"; exit 1; }
[ -f "$SQL_DIR/02_create_catalog.sql" ]        || { echo "BLAD: $SQL_DIR/02_create_catalog.sql nie istnieje"; exit 1; }

log "=== RMAN Recovery Catalog setup on rcat01 ==="

log "1) Pre-flight: PDB RCATPDB open?"
sqlplus -S / as sysdba <<EOF
SET HEADING OFF FEEDBACK OFF
SELECT 'PDB ' || name || ' STATUS=' || open_mode FROM v\$pdbs WHERE name='RCATPDB';
EXIT
EOF

log "2) Listener service RCATPDB?"
lsnrctl status | grep -i RCATPDB || log "[WARN] RCATPDB nie zarejestrowany. Sprobuj: ALTER SYSTEM REGISTER;"

log "3) Tworze schemat rman_cat (sql/01)..."
# Przekazujemy LAB_PASS jako pozycyjny parametr &1 dla CREATE USER ... IDENTIFIED BY
sqlplus -S sys/${RCAT_PWD}@${PDB_TNS} as sysdba @"$SQL_DIR/01_create_catalog_schema.sql" "${LAB_PASS}"

log "4) CREATE CATALOG (rman, sql/02)..."
# Idempotency: jesli katalog istnieje, RMAN zwraca RMAN-06441 + exit code != 0.
# Set +e zeby walidacja w kroku 5 zdecydowala czy stan jest poprawny (zamiast set -e abort).
# Lesson 2026-05-03 iter.9.
set +e
rman catalog rman_cat/${RCAT_PWD}@${PDB_TNS} <<EOF
@$SQL_DIR/02_create_catalog.sql
EOF
RMAN_RC=$?
set -e
if [ $RMAN_RC -ne 0 ]; then
    log "[INFO] RMAN exit $RMAN_RC - moze 'catalog already exists' (re-run). Walidacja w kroku 5 potwierdzi."
fi

log "5) Walidacja: katalog istnieje?"
# UWAGA: katalog RMAN w 26ai/23ai ma okolo:
#   - ~62 base TABLES (catalog metadata: BACKUP_CORRUPTION, BACKUP_PIECE_DETAILS, DBINC, etc.)
#   - ~124 VIEWS z prefixem RCI_* (RMAN Catalog Internal - wyzsze warstwy nad tabelami)
#   - 3 packages + body + ~666 procedur/funkcji
# Lesson 2026-05-03 iter.9: poczatkowy query szukal 'RC_%' (z prefixem) ale w 26ai
# widoki maja prefix 'RCI_' (Internal). Liczymy szeroko: wszystkie tabele + wszystkie views.
# Pelny katalog dla pierwszej walidacji: tables>=50 AND views>=50.
# RMAN catalog in 26ai/23ai: ~62 base tables, ~124 RCI_* views, 3 packages.
# Lesson: views use 'RCI_' prefix in 26ai (RMAN Catalog Internal), not 'RC_'.
sqlplus -S rman_cat/${RCAT_PWD}@${PDB_TNS} <<EOF
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT 'Catalog tables (base): ' || COUNT(*) FROM user_tables;
SELECT 'Catalog views (RCI_*): ' || COUNT(*) FROM user_views;
SELECT 'Catalog packages: ' || COUNT(*) FROM user_objects WHERE object_type='PACKAGE';
SELECT 'Total objects: ' || COUNT(*) FROM user_objects;
SELECT CASE WHEN COUNT(*) >= 50 THEN '[OK] Katalog kompletny (>=50 tables)' ELSE '[WARN] Niedopelniony katalog (<50 tables)' END FROM user_tables;
EXIT
EOF

log "=== RMAN Catalog setup complete ==="
log ""
log "Nastepny krok: rejestracja PRIM"
log "  Skopiuj sql/03_register_databases.sql na prim01 i uruchom jako oracle:"
log "  rman target / catalog rman_cat/${RCAT_PWD}@${PDB_TNS} @03_register_databases.sql"
log ""
log "Lub wywolaj catalog_register_prim.sh ktore zrobi to przez SSH."
