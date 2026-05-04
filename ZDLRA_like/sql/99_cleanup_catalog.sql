# ==============================================================================
# Tytul:        99_cleanup_catalog.sql
# Opis:         Cleanup script: UNREGISTER baz + DROP CATALOG. Uzywaj OSTROZNIE.
#               Usuwa metadane backupow z katalogu - same backup files na dysku
#               pozostaja, ale RMAN nie bedzie ich znal jako rejestrowane.
# Description [EN]: Cleanup: UNREGISTER databases + DROP CATALOG. USE WITH CAUTION.
#                   Removes catalog metadata. Backup files on disk remain but RMAN
#                   loses awareness of them.
#
# UWAGA: RMAN uzywa # jako komentarz (NIE -- jak SQL). Sprawdzone empirycznie 2026-05-04 iter.12.
# NOTE:  RMAN uses # for comments (not --). Verified 2026-05-04 iter.12.
#        RMAN-02001 'unrecognized punctuation symbol' przy --
#
# Autor:        KCB Kris
# Data:         2026-05-04 (v1.1: # zamiast --, lesson #9 zastosowany retroactively)
# Wersja:       1.1
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Uzycie [PL]:  rman target / catalog rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB \
#                    @99_cleanup_catalog.sql
# Usage [EN]:   Same. ONLY when rebuilding catalog from scratch!
# ==============================================================================

# KROK 1: UNREGISTER bazy PRIM (zachowaj backup files)
UNREGISTER DATABASE PRIM NOPROMPT;

# KROK 2: DROP CATALOG (usun wszystkie tabele rman_cat)
# UWAGA: po tym potrzeba zrobic CREATE CATALOG od nowa!
DROP CATALOG;

EXIT
