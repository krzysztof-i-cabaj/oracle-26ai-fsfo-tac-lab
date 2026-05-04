# ==============================================================================
# Tytul:        02_create_catalog.sql
# Opis:         Tworzy faktyczny katalog RMAN (CREATE CATALOG) w schemacie rman_cat.
#               Uruchamiac PRZEZ RMAN (nie SQLPlus!).
# Description [EN]: Creates the actual RMAN catalog (CREATE CATALOG) in rman_cat schema.
#                   Run via RMAN (not SQLPlus!).
#
# UWAGA: RMAN uzywa # jako komentarz (nie -- jak SQL).
#        DBMS_OUTPUT/PL/SQL nie dziala w RMAN - tylko polecenia RMAN + 'SQL "..."' dla SQL.
# NOTE:  RMAN uses # for comments (not --). PL/SQL doesn't work in RMAN - only RMAN
#        commands + 'SQL "..."' for inline SQL.
# Lesson learned 2026-05-03 iter.9: poprzednia wersja miala SQL-style '--' comments
# w headerze + EXECUTE DBMS_OUTPUT - oba crash z RMAN-02001/RMAN-00558.
#
# Autor:        KCB Kris
# Data:         2026-05-03 (v1.1: # zamiast -- + usuniety EXECUTE)
# Wersja:       1.1
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - 01_create_catalog_schema.sql wykonany
#                    - Listener na rcat01 zarejestrowal serwis RCATPDB
# Requirements [EN]: - 01 script done, listener has RCATPDB registered.
#
# Uzycie [PL]:  rman catalog rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB @02_create_catalog.sql
# Usage [EN]:   rman catalog rman_cat/...@rcat01:1521/RCATPDB @02_create_catalog.sql
#               (lub interaktywnie: RMAN> @02_create_catalog.sql / or interactive)
# ==============================================================================

# CREATE CATALOG nie ma natywnej IF-NOT-EXISTS - re-run failuje z RMAN-06441.
# Workaround: ignoruj exit code (catalog_create.sh ma osobna walidacje w kroku 5
# przez sqlplus ktora policzy tabele RC_* w schemacie rman_cat).
# CREATE CATALOG has no native IF-NOT-EXISTS - re-run fails with RMAN-06441.
# Workaround: ignore via wrapping (catalog_create.sh has separate validation in step 5).
# Lesson 2026-05-03 iter.9.
CREATE CATALOG;

# UWAGA: NIE uzywaj tu 'SQL "..."' dla walidacji - SQL command w RMAN
# wykonuje SQL na target database (ktorej tu nie mamy podlaczonej, tylko catalog).
# Walidacja musi byc OSOBNO przez sqlplus -S rman_cat/...@PDB_TNS - patrz catalog_create.sh:71-75.
# IMPORTANT: do NOT use 'SQL "..."' here for validation - SQL command in RMAN runs against
# target database (we only have catalog connection here). Validation must be separate sqlplus.

EXIT
