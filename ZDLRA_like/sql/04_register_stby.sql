# ==============================================================================
# Tytul:        04_register_stby.sql
# Opis:         Dodaje STBY jako site w katalogu RMAN (CONFIGURE DB_UNIQUE_NAME).
#               Uruchamiac PRZEZ RMAN z TARGET=PRIMARY (prim01), CATALOG=rcat01.
# Description [EN]: Adds STBY as a site in the RMAN catalog (CONFIGURE DB_UNIQUE_NAME).
#                   Run via RMAN with TARGET=PRIMARY (prim01), CATALOG=rcat01.
#
# UWAGA: RMAN uzywa # jako komentarz (NIE -- jak SQL). Sprawdzone empirycznie 2026-05-03 iter.9.
# NOTE:  RMAN uses # for comments (not --). Verified 2026-05-03 iter.9.
#
# Wzorzec / Pattern:
#   PRIM (TARGET=PRIMARY) --CONFIGURE DB_UNIQUE_NAME 'STBY' CONNECT IDENTIFIER 'STBY'--> rcat01
#   (RC_SITE += STBY z tym samym DBID co PRIM)
#
# Autor:        KCB Kris
# Data:         2026-05-04
# Wersja:       1.0
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - PRIM zarejestrowany (sql/03_register_databases.sql wykonany, DBID w rc_database)
#                    - DG broker SUCCESS, prim01=primary, stby01=physical standby (po ew. switchover)
#                    - TNS alias 'STBY' w tnsnames.ora na prim01 (HOST=stby01.lab.local, SERVICE=STBY)
#                    - Z prim01 RMAN moze polaczyc sie do rcat01:1521/RCATPDB
# Requirements [EN]: - PRIM registered, DG broker SUCCESS, TNS 'STBY' on prim01, network to rcat01.
#
# Uzycie [PL]:  Uruchom NA prim01 jako oracle:
#               rman target / catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB" \
#                    @04_register_stby.sql
# Usage [EN]:   Run ON prim01 as oracle, see above.
#
# Idempotencja [PL]: CONFIGURE jest idempotentne - re-run nadpisuje connect identifier
#                    bez bledu (komunikat "old/new RMAN configuration parameters").
# Idempotency [EN]:  CONFIGURE is idempotent - re-run overwrites without error.
# ==============================================================================

# Dodaj STBY jako site w katalogu (RC_SITE += STBY).
# Connect identifier 'STBY' bedzie uzyty przy backupach z primary do auto-connect do standby.
CONFIGURE DB_UNIQUE_NAME 'STBY' CONNECT IDENTIFIER 'STBY';

# Walidacja - powinno pokazac 2 sites: PRIM + STBY (ten sam DBID).
LIST DB_UNIQUE_NAME ALL;

EXIT
