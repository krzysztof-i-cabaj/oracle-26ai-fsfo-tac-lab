# ==============================================================================
# Tytul:        10_rman_config_persistent.sql
# Opis:         Persistent RMAN configuration dla bazy PRIM (zarejestrowanej w
#               katalogu na rcat01). Ustawia retention policy, kanaly, kompresje,
#               autobackup. Uruchamiac PRZEZ RMAN polaczony do TARGET=PRIM.
# Description [EN]: Persistent RMAN config for PRIM (registered in rcat01 catalog).
#                   Run via RMAN connected to TARGET=PRIM, CATALOG=rcat01.
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
# Uzycie [PL]:  Na prim01 jako oracle:
#               rman target / catalog rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB \
#                    @10_rman_config_persistent.sql
# Usage [EN]:   Same.
# ==============================================================================

# Retention: zachowuj dane potrzebne do recovery z dowolnego punktu w ostatnich 14 dniach
CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 14 DAYS;

# Optymalizacja: nie backupuj bloku ktory zostal juz zbackupowany (incremental friendly)
CONFIGURE BACKUP OPTIMIZATION ON;

# Autobackup controlfile + spfile po kazdej zmianie struktury (krytyczne dla disaster recovery)
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '/mnt/rman_bck/cf/cf_%F';

# Domyslny device type i parallelism
CONFIGURE DEVICE TYPE DISK PARALLELISM 4 BACKUP TYPE TO BACKUPSET;

# Compression: 'MEDIUM' = basic compression (BEZ licencji ACO).
# 'LOW' i 'HIGH' wymagaja Advanced Compression Option.
CONFIGURE COMPRESSION ALGORITHM 'MEDIUM';

# Domyslny format dla backupow do disk channel
CONFIGURE CHANNEL DEVICE TYPE DISK FORMAT '/mnt/rman_bck/full/bp_%U';

# Archivelog deletion policy: kasuj dopiero po 2x backupowaniu
# (jeden lokalnie /mnt/rman_bck/arch, drugi do FRA lub osobny tag)
CONFIGURE ARCHIVELOG DELETION POLICY TO BACKED UP 2 TIMES TO DISK;

# Snapshot controlfile location (potrzebne dla RAC i online backup)
CONFIGURE SNAPSHOT CONTROLFILE NAME TO '/u01/app/oracle/snapcf_PRIM.f';

# Wyswietl aktualna konfiguracje
SHOW ALL;

EXIT
