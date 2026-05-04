# ==============================================================================
# Tytul:        05_resync_stby.sql
# Opis:         Resync katalogu RMAN z standby controlfile.
#               Uruchamiac PRZEZ RMAN z TARGET=STANDBY (stby01), CATALOG=rcat01.
# Description [EN]: Resyncs RMAN catalog from standby controlfile.
#                   Run via RMAN with TARGET=STANDBY (stby01), CATALOG=rcat01.
#
# UWAGA: RMAN uzywa # jako komentarz (NIE -- jak SQL). Sprawdzone empirycznie 2026-05-03 iter.9.
# NOTE:  RMAN uses # for comments (not --). Verified 2026-05-03 iter.9.
#
# Wzorzec / Pattern:
#   STBY (TARGET=STANDBY) --RESYNC CATALOG FROM DB_UNIQUE_NAME 'STBY'--> rcat01
#   (metadata standby controlfile -> katalog; LIST BACKUP/COPY widzi backupy zrobione na stby)
#
# Autor:        KCB Kris
# Data:         2026-05-04
# Wersja:       1.0
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - 04_register_stby.sql wykonany na primary (RC_SITE ma STBY)
#                    - stby01 w roli PHYSICAL STANDBY, MOUNTED lub READ ONLY WITH APPLY
#                    - Z stby01 RMAN moze polaczyc sie do rcat01:1521/RCATPDB
# Requirements [EN]: - 04_* run on primary (RC_SITE has STBY), stby01 is PHYSICAL STANDBY,
#                      network from stby01 to rcat01.
#
# Uzycie [PL]:  Uruchom NA stby01 jako oracle:
#               rman target / catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB" \
#                    @05_resync_stby.sql
# Usage [EN]:   Run ON stby01 as oracle, see above.
#
# Idempotencja [PL]: RESYNC jest idempotentne - re-run pobiera metadane ponownie bez bledu.
# Idempotency [EN]:  RESYNC is idempotent - re-run pulls metadata again without error.
# ==============================================================================

# Pobierz metadane z standby controlfile do katalogu.
# Po tym kroku RC_BACKUP_PIECE/RC_BACKUP_COPY widza backupy zrobione na stby.
RESYNC CATALOG FROM DB_UNIQUE_NAME 'STBY';

# Walidacja - powinno pokazac 2 sites (PRIM + STBY).
LIST DB_UNIQUE_NAME ALL;

EXIT
