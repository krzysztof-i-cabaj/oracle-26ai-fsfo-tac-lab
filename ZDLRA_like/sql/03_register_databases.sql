# ==============================================================================
# Tytul:        03_register_databases.sql
# Opis:         Rejestruje baze PRIM (RAC) w katalogu RMAN na rcat01.
#               Uruchamiac PRZEZ RMAN z polaczeniem do TARGET=PRIM, CATALOG=rcat01.
# Description [EN]: Registers PRIM database in RMAN catalog on rcat01.
#                   Run via RMAN with TARGET=PRIM, CATALOG=rcat01.
#
# UWAGA: RMAN uzywa # jako komentarz (NIE -- jak SQL). Sprawdzone empirycznie 2026-05-03 iter.9.
# NOTE:  RMAN uses # for comments (not --). Verified 2026-05-03 iter.9.
#
# Autor:        KCB Kris
# Data:         2026-05-03 (v1.1: # zamiast --)
# Wersja:       1.1
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - Katalog stworzony (02_create_catalog.sql)
#                    - PRIM dostepny przez TNS (tnsnames.ora ma wpis PRIM lub bezposrednie connect)
#                    - Z PRIM (np. prim01) RMAN moze polaczyc sie do rcat01:1521
# Requirements [EN]: - Catalog created, PRIM TNS reachable, network from PRIM to rcat01
#
# Uzycie [PL]:  Uruchom NA prim01 jako oracle:
#               rman target / catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB" \
#                    @03_register_databases.sql
# Usage [EN]:   Run ON prim01 as oracle, see above.
# ==============================================================================

# Idempotency: REGISTER DATABASE failuje z RMAN-20002 jesli juz zarejestrowana.
# Re-run tolerujemy w wrapperze catalog_register_prim.sh (set +e).
# Re-run is tolerated by wrapper catalog_register_prim.sh (set +e).
REGISTER DATABASE;

# Pierwsza synchronizacja metadanych (pobiera info z controlfile do katalogu)
RESYNC CATALOG;

# Sprawdzenie rejestracji
LIST DB_UNIQUE_NAME ALL;

REPORT SCHEMA;

EXIT
