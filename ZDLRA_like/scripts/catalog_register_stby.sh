#!/bin/bash
# ==============================================================================
# Tytul:        catalog_register_stby.sh
# Opis:         Rejestruje fizyczna baze STANDBY (STBY) w katalogu RMAN na rcat01.
#               Wzorzec: CONFIGURE DB_UNIQUE_NAME na PRIM + RESYNC CATALOG FROM na STBY.
#               Wywoluje sql/04_register_stby.sql (na prim01) + sql/05_resync_stby.sql (na stby01).
# Description [EN]: Registers physical STANDBY in RMAN catalog using
#                   CONFIGURE DB_UNIQUE_NAME on PRIM + RESYNC CATALOG FROM on STBY pattern.
#
# Autor:        KCB Kris
# Data:         2026-05-04
# Wersja:       1.0
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - Uruchamiac NA rcat01 (lub innym hoscie z SSH key do oracle@prim01 + oracle@stby01)
#                    - PRIM zarejestrowany (catalog_register_prim.sh wykonany)
#                    - DG broker SUCCESS, prim01=PRIMARY, stby01=PHYSICAL STANDBY
#                    - TNS aliasy 'STBY' na prim01 i 'PRIM' na stby01 (wskazuja na siebie nawzajem)
#                    - SSH equiv oracle@rcat01 -> oracle@prim01 i oracle@rcat01 -> oracle@stby01
# Requirements [EN]: - Run on rcat01, PRIM registered, DG broker SUCCESS, TNS aliases set up,
#                      SSH equiv to both DB nodes.
#
# Uzycie [PL]:  bash catalog_register_stby.sh
# Usage [EN]:   bash catalog_register_stby.sh
#
# Wzorzec / Pattern:
#   PRIM (TARGET=PRIMARY) --CONFIGURE DB_UNIQUE_NAME 'STBY' CONNECT IDENTIFIER 'STBY'--> rcat01
#   STBY (TARGET=STANDBY) --RESYNC CATALOG FROM DB_UNIQUE_NAME 'STBY'--> rcat01
#
# UWAGA o rolach DG / DG role caveat:
#   CONFIGURE DB_UNIQUE_NAME wykonuje sie z TARGET=baza w roli PRIMARY.
#   Po FSFO failover-ze role moga byc odwrocone (stby01=PRIMARY, prim01=STANDBY) -
#   skrypt wykryje ten stan i wyjdzie z bledem (user musi zrobic switchover).
# ==============================================================================

set -euo pipefail

# --- LAB secrets (konwencja VMs2-install) ---
[ -r /root/.lab_secrets ] && source /root/.lab_secrets
[ -r "$HOME/.lab_secrets" ] && source "$HOME/.lab_secrets"
if [ -z "${LAB_PASS:-}" ]; then
    echo "BLAD: LAB_PASS nieustawiona. Stworz /root/.lab_secrets z 'export LAB_PASS=...' (chmod 600)."
    echo "ERROR: LAB_PASS not set. Create /root/.lab_secrets with 'export LAB_PASS=...' (chmod 600)."
    exit 1
fi

log() { echo "[$(date +%H:%M:%S)] $*"; }

PRIM_HOST="prim01.lab.local"
STBY_HOST="stby01.lab.local"
DB_USER="oracle"
RCAT_TNS="rcat01:1521/RCATPDB"
RCAT_USER="rman_cat"
RCAT_PWD="${LAB_PASS}"

PRIM_DB_UNIQUE_NAME="PRIM"
STBY_DB_UNIQUE_NAME="STBY"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_CONFIGURE="$SCRIPT_DIR/../sql/04_register_stby.sql"
SQL_RESYNC="$SCRIPT_DIR/../sql/05_resync_stby.sql"

[ -f "$SQL_CONFIGURE" ] || { echo "BLAD: $SQL_CONFIGURE nie istnieje"; exit 1; }
[ -f "$SQL_RESYNC" ]    || { echo "BLAD: $SQL_RESYNC nie istnieje"; exit 1; }

log "=== Rejestracja STBY w katalogu RMAN ==="

# ----------------------------------------------------------------------
# 1) Pre-check: role DG sa zgodne z naming convention
# ----------------------------------------------------------------------
log "1) Sprawdzam role DG (prim01 musi byc PRIMARY, stby01 - PHYSICAL STANDBY)..."

PRIM_ROLE=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ${DB_USER}@${PRIM_HOST} \
    "bash -lc 'sqlplus -S / as sysdba <<EOF
SET HEADING OFF FEEDBACK OFF PAGES 0
SELECT database_role FROM v\\\$database;
EXIT
EOF'" 2>/dev/null | tr -d '[:space:]')

STBY_ROLE=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ${DB_USER}@${STBY_HOST} \
    "bash -lc 'sqlplus -S / as sysdba <<EOF
SET HEADING OFF FEEDBACK OFF PAGES 0
SELECT database_role FROM v\\\$database;
EXIT
EOF'" 2>/dev/null | tr -d '[:space:]')

log "   prim01 role: ${PRIM_ROLE}"
log "   stby01 role: ${STBY_ROLE}"

if [ "${PRIM_ROLE}" != "PRIMARY" ]; then
    log "[FAIL] prim01 NIE jest PRIMARY (role=${PRIM_ROLE})."
    log "       Po FSFO role moga byc odwrocone. Wykonaj switchover do PRIM przed re-run:"
    log "       ssh infra01 \"TNS_ADMIN=/etc/oracle/tns/obs_ext dgmgrl /@PRIM_ADMIN 'SWITCHOVER TO PRIM'\""
    exit 1
fi
if [ "${STBY_ROLE}" != "PHYSICALSTANDBY" ]; then
    log "[FAIL] stby01 NIE jest PHYSICAL STANDBY (role=${STBY_ROLE})."
    exit 1
fi

# ----------------------------------------------------------------------
# 2) Pre-check: TNS alias 'STBY' z prim01 jest reachable
# ----------------------------------------------------------------------
log "2) Test TNS reachability 'STBY' z prim01..."
ssh -o StrictHostKeyChecking=no ${DB_USER}@${PRIM_HOST} \
    "bash -lc 'tnsping STBY 2>&1 | tail -3'" \
    || { log "[FAIL] prim01 nie widzi TNS 'STBY'. Dodaj wpis do tnsnames.ora."; exit 1; }

# ----------------------------------------------------------------------
# 3) Pre-check: rcat01 reachable z stby01
# ----------------------------------------------------------------------
log "3) Test reachability rcat01 z stby01..."
ssh -o StrictHostKeyChecking=no ${DB_USER}@${STBY_HOST} \
    "bash -lc 'tnsping ${RCAT_TNS} 2>&1 | tail -3'" \
    || { log "[FAIL] stby01 nie widzi rcat01:1521. Sprawdz siec/listener."; exit 1; }

# ----------------------------------------------------------------------
# 4) Kopiuje SQL na prim01 (CONFIGURE) + stby01 (RESYNC)
# ----------------------------------------------------------------------
log "4) Kopiuje SQL na prim01 i stby01..."
scp -o StrictHostKeyChecking=no "$SQL_CONFIGURE" ${DB_USER}@${PRIM_HOST}:/tmp/04_register_stby.sql
scp -o StrictHostKeyChecking=no "$SQL_RESYNC"    ${DB_USER}@${STBY_HOST}:/tmp/05_resync_stby.sql

# ----------------------------------------------------------------------
# 5) RMAN na prim01: CONFIGURE DB_UNIQUE_NAME 'STBY' CONNECT IDENTIFIER 'STBY'
# ----------------------------------------------------------------------
log "5) Uruchamiam RMAN na prim01 (TARGET=PRIMARY): CONFIGURE DB_UNIQUE_NAME..."
# Quoting: connect string w cudzyslowach bo $LAB_PASS moze zawierac '!' (bash history expansion).
ssh -o StrictHostKeyChecking=no ${DB_USER}@${PRIM_HOST} bash <<SSHEOF
set -e
source ~/.bash_profile
rman target / catalog "${RCAT_USER}/${RCAT_PWD}@${RCAT_TNS}" <<RMAN
@/tmp/04_register_stby.sql
RMAN
SSHEOF

# ----------------------------------------------------------------------
# 6) RMAN na stby01: RESYNC CATALOG FROM DB_UNIQUE_NAME 'STBY'
# ----------------------------------------------------------------------
log "6) Uruchamiam RMAN na stby01 (TARGET=STANDBY): RESYNC CATALOG FROM 'STBY'..."
ssh -o StrictHostKeyChecking=no ${DB_USER}@${STBY_HOST} bash <<SSHEOF
set -e
source ~/.bash_profile
rman target / catalog "${RCAT_USER}/${RCAT_PWD}@${RCAT_TNS}" <<RMAN
@/tmp/05_resync_stby.sql
RMAN
SSHEOF

# ----------------------------------------------------------------------
# 7) Walidacja: RC_SITE musi pokazac 2 wiersze (PRIM + STBY, ten sam DBID)
# ----------------------------------------------------------------------
log "7) Walidacja na rcat01: RC_SITE JOIN RC_DATABASE powinno pokazac PRIM + STBY..."
# UWAGA: w 26ai RC_SITE NIE ma kolumn DBID/DB_NAME (lesson learned 2026-05-04 iter.11).
# Trzeba JOIN do RC_DATABASE po DB_KEY zeby pokazac DBID (i ze jest ten sam dla obu sites).
# NOTE: in 26ai RC_SITE has no DBID/DB_NAME columns - JOIN RC_DATABASE on DB_KEY required.
sqlplus -S ${RCAT_USER}/${RCAT_PWD}@${RCAT_TNS} <<SQLEOF
SET HEADING ON FEEDBACK ON LINESIZE 150 PAGESIZE 50
COLUMN db_unique_name FORMAT A20 HEADING "DB Unique Name"
COLUMN database_role  FORMAT A18 HEADING "DG Role"
COLUMN db_name        FORMAT A12 HEADING "DB Name"
COLUMN dbid           FORMAT 99999999999 HEADING "DBID"
COLUMN site_key       FORMAT 99999 HEADING "Site Key"

SELECT s.site_key, s.db_unique_name, s.database_role, d.name AS db_name, d.dbid
  FROM rc_site s
  JOIN rc_database d ON s.db_key = d.db_key
 ORDER BY s.db_unique_name;

EXIT
SQLEOF

log "=== STBY zarejestrowany w katalogu RMAN ==="
log ""
log "Walidacja oczekiwana:"
log "  RC_SITE  --> 2 wiersze (PRIM + STBY, ten sam DBID, rozne db_unique_name)"
log "  RC_DATABASE --> 1 wiersz (grupowanie po DBID)"
log ""
log "Sprint 1 step 3 = DONE. Mozesz przejsc do Sprint 2 (Doc 06 Backup Policy)."
