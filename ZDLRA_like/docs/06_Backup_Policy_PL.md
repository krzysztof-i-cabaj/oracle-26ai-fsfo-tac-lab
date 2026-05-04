# 🗓️ 06 — Backup Policy (Sprint 2)

[![Sprint](https://img.shields.io/badge/Sprint-2-blue)]()
[![Component](https://img.shields.io/badge/Component-RMAN_Policy-red)]()
[![Cycles](https://img.shields.io/badge/Cycles-Weekly%20%2B%20Daily%20%2B%2015min-success)]()
[![Retention](https://img.shields.io/badge/Retention-14_days-orange)]()
[![Compression](https://img.shields.io/badge/Compression-Basic_%22MEDIUM%22-darkgreen)]()

> 🎯 Polityka cykli backupowych dla bazy PRIM: tygodniowy Level 0 + dzienny incremental L1 + archivelog co 15 min.

## 📊 Cykle backupowe / Backup cycles

| Typ | Częstotliwość | Skrypt | Retention | Lokalizacja |
|---|---|---|---|---|
| **Full L0** | tygodniowo (niedz 02:00) | `rman_full_backup.sh` | 4 tygodnie | `/mnt/rman_bck/full/` |
| **Incremental L1 cumulative** | codziennie (02:00) | `rman_incremental_l1.sh` | 7 dni | `/mnt/rman_bck/incr/` |
| **Archivelog** | co 15 min | `rman_archivelog_only.sh` | aż do BACKED_UP 2 razy | `/mnt/rman_bck/arch/` |
| **Controlfile autobackup** | po każdej zmianie struktury | (automatyczne) | overlay z FULL | `/mnt/rman_bck/cf/` |
| **Crosscheck + cleanup** | tygodniowo | `rman_crosscheck.sh` | — | — |
| **Validate** | tygodniowo (po FULL) | `rman_validate.sh` | — | — |

## ⚙️ Persistent RMAN config (jednorazowy setup)

[PL] Polityka backupowa = persystentne ustawienia RMAN zapisane w katalogu (`rcat01`). Wykonujemy **jednorazowo** po zarejestrowaniu PRIM (Sprint 1 step 3a). Sam plik źródłowy: [`sql/10_rman_config_persistent.sql`](../sql/10_rman_config_persistent.sql).

[EN] Backup policy = persistent RMAN settings stored in the catalog (`rcat01`). Run **once** after registering PRIM (Sprint 1 step 3a). Source: [`sql/10_rman_config_persistent.sql`](../sql/10_rman_config_persistent.sql).

### 📋 Pre-checks

- ✅ PRIM zarejestrowany w katalogu (`SELECT name, dbid FROM rc_database;` zwraca PRIM)
- ✅ `/mnt/rman_bck` zamontowany na prim01 (`mount | grep rman_bck`)
- ✅ Logujesz sie jako `oracle` na prim01 (`whoami` = oracle)

### 🚀 Metoda A — automatyczna (zalecane)

**Wariant 1 — lokalnie na prim01:**

```bash
ssh oracle@prim01
bash /tmp/scripts/rman_setup_config.sh
```

**Wariant 2 — zdalnie z rcat01 (po `ssh_setup.sh` z full mesh):**

```bash
ssh oracle@rcat01 'ssh oracle@prim01 "bash /tmp/scripts/rman_setup_config.sh"'
```

Skrypt:
1. Source LAB_PASS, weryfikuje pre-checks (oracle user, sql file, /mnt/rman_bck).
2. Tworzy subkatalogi `/mnt/rman_bck/{cf,full,incr,arch}` jeśli brak.
3. `rman target / catalog ... @sql/10_rman_config_persistent.sql` — wykonuje 9 CONFIGURE.
4. Walidacja: `SHOW RETENTION POLICY; SHOW BACKUP OPTIMIZATION; ... SHOW SNAPSHOT CONTROLFILE NAME;` — 9 wpisów potwierdzonych.

**Idempotencja:** CONFIGURE w RMAN nadpisuje wartości bez błędu, więc re-run jest bezpieczny.

### 🛠️ Metoda B — manualna (interaktywnie)

```bash
# Krok 1: SSH na prim01 jako oracle
ssh oracle@prim01

# Krok 2: Polacz sie do RMAN z TARGET=PRIM (lokalny os auth) i CATALOG=rcat01
# UWAGA: $LAB_PASS zawiera '!' - uzyj single quotes lub ${LAB_PASS} w double quotes.
rman target / catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB"
```

**Wariant 2a — przez plik SQL (zalecane manualne):**

```rman
RMAN> @/tmp/sql/10_rman_config_persistent.sql
# Wykonuje 9 CONFIGURE + SHOW ALL na koncu

RMAN> EXIT;
```

**Wariant 2b — linia po linii:**

```rman
RMAN> CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 14 DAYS;
RMAN> CONFIGURE BACKUP OPTIMIZATION ON;
RMAN> CONFIGURE CONTROLFILE AUTOBACKUP ON;
RMAN> CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '/mnt/rman_bck/cf/cf_%F';
RMAN> CONFIGURE DEVICE TYPE DISK PARALLELISM 4 BACKUP TYPE TO BACKUPSET;
RMAN> CONFIGURE COMPRESSION ALGORITHM 'MEDIUM';
RMAN> CONFIGURE CHANNEL DEVICE TYPE DISK FORMAT '/mnt/rman_bck/full/bp_%U';
RMAN> CONFIGURE ARCHIVELOG DELETION POLICY TO BACKED UP 2 TIMES TO DISK;
RMAN> CONFIGURE SNAPSHOT CONTROLFILE NAME TO '/u01/app/oracle/snapcf_PRIM.f';

RMAN> SHOW ALL;
RMAN> EXIT;
```

> 💡 **`COMPRESSION ALGORITHM 'MEDIUM'`** = basic compression. Bez licencji ACO. `LOW`/`HIGH` wymagają ACO — **nie zakładamy**.

### ✅ Walidacja po setupie

```bash
# Z dowolnego klienta z dostepem do rcat01 (host, rcat01, prim01)
rman target / catalog rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB
RMAN> SHOW ALL;
```

Oczekiwane (9 ustawień persystentnych zapisanych w katalogu):

| # | CONFIGURE | Oczekiwana wartosc |
|---|---|---|
| 1 | RETENTION POLICY | `RECOVERY WINDOW OF 14 DAYS` |
| 2 | BACKUP OPTIMIZATION | `ON` |
| 3 | CONTROLFILE AUTOBACKUP | `ON` |
| 4 | CONTROLFILE AUTOBACKUP FORMAT | `/mnt/rman_bck/cf/cf_%F` |
| 5 | DEVICE TYPE DISK | `PARALLELISM 4 BACKUP TYPE TO BACKUPSET` |
| 6 | COMPRESSION ALGORITHM | `MEDIUM` |
| 7 | CHANNEL DEVICE TYPE DISK FORMAT | `/mnt/rman_bck/full/bp_%U` |
| 8 | ARCHIVELOG DELETION POLICY | `BACKED UP 2 TIMES TO DISK` |
| 9 | SNAPSHOT CONTROLFILE NAME | `/u01/app/oracle/snapcf_PRIM.f` |

## 🔁 Wykonywanie cykli backupowych / Running backup cycles

[PL] Wszystkie skrypty backupowe uruchamiamy **z prim01 jako oracle** (TARGET=local). W tej części LAB-u (`_RecoveryAppliance_/`) maszyny są **często wyłączane** — cron praktycznie nigdy się nie wykona dla planowanych okien (`niedz 02:00` itd.). Dlatego **default = manual on-demand**.

[EN] All backup scripts are run **from prim01 as oracle** (TARGET=local). In this LAB part the VMs are **often powered off** — cron jobs barely ever fire on scheduled windows. Default workflow: **manual on-demand**.

### 📋 Workflow LAB-u — manual on-demand (default)

Po włączeniu LAB-u i przed pracą nad backupami uruchamiaj te skrypty **wybiórczo**, w zależności od scenariusza:

| Skrypt | Co robi | Kiedy uruchomić | Komenda (z hosta lub po `ssh prim01`) |
|---|---|---|---|
| **`rman_full_backup.sh`** | FULL L0 (Level 0) + ARCHIVELOG + autobackup CF | Pierwszy backup po setupie polityki, "świeża baza" dla Sprint 2 | `ssh oracle@prim01 'bash /tmp/scripts/rman_full_backup.sh'` |
| **`rman_incremental_l1.sh`** | Incremental L1 CUMULATIVE + ARCHIVELOG | Po FULL — testuje że incremental działa po Level 0 | `ssh oracle@prim01 'bash /tmp/scripts/rman_incremental_l1.sh'` |
| **`rman_archivelog_only.sh`** | Backup samych archivelogów (lekki, szybki) | Częste przełączenia logów / przed switchover DG / przed shutdown LAB | `ssh oracle@prim01 'bash /tmp/scripts/rman_archivelog_only.sh'` |
| **`rman_crosscheck.sh`** | CROSSCHECK + DELETE EXPIRED + DELETE OBSOLETE | Po sztucznym usunięciu plików backup z dysku / czyszczenie katalogu | `ssh oracle@prim01 'bash /tmp/scripts/rman_crosscheck.sh'` |
| **`rman_validate.sh`** | RESTORE DATABASE VALIDATE — sprawdza integralność backupów bez restore | Po FULL+INCR — pewność że backupy są używalne | `ssh oracle@prim01 'bash /tmp/scripts/rman_validate.sh'` |

> 💡 **Sugerowana sekwencja "od zera" po włączeniu LAB-u** (jeśli chcesz świeże dane dla scenariuszy B-1..B-6):
> ```bash
> ssh oracle@prim01 'bash /tmp/scripts/rman_full_backup.sh'        # 1. FULL L0 (~2-5 min)
> ssh oracle@prim01 'bash /tmp/scripts/rman_incremental_l1.sh'     # 2. INCR L1 (~30 sek)
> ssh oracle@prim01 'bash /tmp/scripts/rman_archivelog_only.sh'    # 3. ARCH (~10 sek)
> ssh oracle@prim01 'bash /tmp/scripts/rman_validate.sh'           # 4. VALIDATE (~1-2 min)
> ```

### 📝 Manualne polecenia RMAN (copy/paste, bez wrappera)

[PL] Czasem łatwiej wkleić surowe komendy RMAN niż uruchamiać skrypt — np. dla ad-hoc backupu, debugowania, edukacji, lub gdy skrypt failuje a trzeba zrozumieć dlaczego. Poniżej gotowe bloki do skopiowania.

[EN] Sometimes it's easier to paste raw RMAN commands than to run a script — e.g. ad-hoc backup, debugging, education, or when the script fails and you need to understand why. Ready-to-paste blocks below.

```bash
# Krok 1: SSH + RMAN connect (wspolny dla wszystkich operacji ponizej)
ssh oracle@prim01
rman target / catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB"
```

#### 🔵 FULL backup (Level 0)

```rman
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK FORMAT '/mnt/rman_bck/full/db_%d_%T_%U';
  ALLOCATE CHANNEL c2 DEVICE TYPE DISK FORMAT '/mnt/rman_bck/full/db_%d_%T_%U';
  ALLOCATE CHANNEL c3 DEVICE TYPE DISK FORMAT '/mnt/rman_bck/full/db_%d_%T_%U';
  ALLOCATE CHANNEL c4 DEVICE TYPE DISK FORMAT '/mnt/rman_bck/full/db_%d_%T_%U';
  BACKUP
    INCREMENTAL LEVEL 0
    AS COMPRESSED BACKUPSET
    TAG 'manual_full'
    DATABASE
    PLUS ARCHIVELOG
      FORMAT '/mnt/rman_bck/arch/arc_%d_%T_%U'
      DELETE INPUT;
  RELEASE CHANNEL c1; RELEASE CHANNEL c2; RELEASE CHANNEL c3; RELEASE CHANNEL c4;
}
```

> 💡 **Skrót dzieki CONFIGURE:** możesz pominąć cały `RUN { }` block i RMAN użyje domyślnych kanałów z `CONFIGURE DEVICE TYPE DISK PARALLELISM 4`:
> ```rman
> BACKUP INCREMENTAL LEVEL 0 AS COMPRESSED BACKUPSET TAG 'manual_full' DATABASE PLUS ARCHIVELOG;
> ```

#### 🟡 Incremental Level 1 (CUMULATIVE)

```rman
BACKUP
  INCREMENTAL LEVEL 1 CUMULATIVE
  AS COMPRESSED BACKUPSET
  TAG 'manual_incr'
  FORMAT '/mnt/rman_bck/incr/incr_%d_%T_%U'
  DATABASE
  PLUS ARCHIVELOG;
```

#### 🟢 Archivelog only (lekki, szybki)

```rman
BACKUP
  AS COMPRESSED BACKUPSET
  TAG 'manual_arch'
  FORMAT '/mnt/rman_bck/arch/arc_%d_%T_%U'
  ARCHIVELOG ALL
  NOT BACKED UP 1 TIMES
  DELETE ALL INPUT;
```

#### 🔍 Crosscheck + cleanup (synchronizuj katalog z dyskiem)

```rman
CROSSCHECK BACKUP;
CROSSCHECK ARCHIVELOG ALL;

DELETE NOPROMPT EXPIRED BACKUP;
DELETE NOPROMPT EXPIRED ARCHIVELOG ALL;
DELETE NOPROMPT OBSOLETE;
```

#### ✅ Validate (sprawdz integralnosc bez restore)

```rman
RESTORE DATABASE VALIDATE;
RESTORE ARCHIVELOG ALL VALIDATE;

# Sprawdz konkretny backup set (jesli znasz BS_KEY z RC_BACKUP_SET):
# VALIDATE BACKUPSET <bs_key>;
```

#### 📋 LIST / REPORT (diagnostyka, bez modyfikacji)

```rman
LIST BACKUP SUMMARY;
LIST BACKUP SUMMARY COMPLETED AFTER 'SYSDATE-1';
LIST DB_UNIQUE_NAME ALL;

REPORT SCHEMA;
REPORT NEED BACKUP;
REPORT OBSOLETE;
REPORT UNRECOVERABLE;
```

#### 🚪 Exit

```rman
EXIT
```

---

### ✅ Walidacja po manual run

> ⚠️ **Lesson learned 2026-05-04 iter.12:** w 26ai `RC_BACKUP_SET` **NIE ma** kolumn `INPUT_BYTES`, `OUTPUT_BYTES` ani `COMPRESSION_RATIO`. Bytes są agregowane per-piece w `RC_BACKUP_PIECE.BYTES` — JOIN required. Też: `BACKUP DATABASE` zwraca `BACKUP_TYPE='I' INCREMENTAL_LEVEL=0` (NIE `'D'`!) — klasyczne "FULL" w 26ai jest formalnie *Incremental Level 0*. Codes: **D**=Controlfile autobackup, **I**=Incremental (lvl 0 = full), **L**=Archivelog.

```bash
# Co jest zarejestrowane w katalogu po backupie
sqlplus -S 'rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB' <<'SQL'
SET LINESIZE 160 PAGESIZE 50
COLUMN start_time FORMAT A19
COLUMN backup_type FORMAT A12
COLUMN status FORMAT A6

-- Lista backup_set'ow z ostatniej godziny
SELECT TO_CHAR(start_time,'YYYY-MM-DD HH24:MI:SS') AS start_time,
       backup_type, incremental_level AS lvl, status, pieces, elapsed_seconds AS elapsed_s
  FROM rc_backup_set
 WHERE start_time > SYSDATE - 1/24
 ORDER BY start_time;

-- Bytes per backup_type (JOIN do RC_BACKUP_PIECE)
SELECT s.backup_type, COUNT(*) AS pieces,
       ROUND(SUM(p.bytes)/1024/1024,1) AS total_mb
  FROM rc_backup_set s
  JOIN rc_backup_piece p ON s.bs_key = p.bs_key
 WHERE s.start_time > SYSDATE - 1/24
 GROUP BY s.backup_type
 ORDER BY 1;

EXIT
SQL

# Pliki na dysku (rzeczywiste backup pieces)
ssh oracle@prim01 'du -sh /mnt/rman_bck/{full,incr,arch,cf}/ 2>/dev/null'
```

**Oczekiwane po pierwszym FULL:**
- `D` (controlfile) ~10-20 MB → `/mnt/rman_bck/cf/`
- `I lvl 0` (database) — kilkaset MB → `/mnt/rman_bck/full/`
- `L` (archivelog) ~100-500 MB → `/mnt/rman_bck/arch/`

### 🚀 Production reference — cron snippet (NIE deployujemy w LAB-ie)

> ⚠️ **Tylko jako referencja — w naszym LAB-ie ten cron nie jest deployowany.** VM-y są wyłączane, cron jobs w okresach offline po prostu nigdy się nie wykonają (klasyczny cron nie odrabia zaległości). Dla LAB-u używaj sekcji "Manual on-demand" powyżej. Snippet poniżej dokumentuje **jak wyglądałaby polityka produkcyjna** dla porównania.

```cron
# /var/spool/cron/oracle (na prim01) - PRODUCTION ONLY
# Production only - NOT deployed in this LAB

# Archivelog co 15 min (RPO < 15 min)
*/15 * * * * /home/oracle/scripts/rman_archivelog_only.sh

# Daily incremental L1 - codziennie o 02:00 (poza niedzielami)
0 2 * * 1-6  /home/oracle/scripts/rman_incremental_l1.sh

# Weekly full L0 - niedziela o 02:00
0 2 * * 0    /home/oracle/scripts/rman_full_backup.sh

# Weekly crosscheck - niedziela o 04:00 (po FULL)
0 4 * * 0    /home/oracle/scripts/rman_crosscheck.sh

# Weekly validate - niedziela o 05:00
0 5 * * 0    /home/oracle/scripts/rman_validate.sh
```

**Alternatywy produkcyjne** (dla maszyn które bywają OFF, np. dev environments):
- **`anacron`** — odrabia zaległe zadania po starcie (ale w LAB-ie po booit od razu rusza FULL)
- **systemd timer + `Persistent=true`** — analog anacron-a z journal/observability
- **Cron na rcat01 + SSH do prim01** (orchestrator outside target) — separation-of-duties

Wybór wymaga decyzji **policy** (windows backupowe, capacity planning, monitoring) — poza zakresem naszego LAB-u.

## 📈 RPO / RTO

| Cel | Wartość | Mechanizm |
|---|---|---|
| **RPO** (Recovery Point Objective) | **≤ 15 min** | Archivelog co 15 min |
| **RPO** (z real-time redo, Sprint 3) | **~0 s** (commit-level) | LOG_ARCHIVE_DEST_3 ASYNC do rcat01 |
| **RTO Full Recovery** | **~30-60 min** | Restore L0 + L1 + arch |
| **RTO PITR (single PDB)** | **~10-20 min** | Restore tylko PDB datafiles |
| **RTO Tablespace** | **~5-10 min** | Online tablespace recovery |
| **RTO Controlfile loss** | **~15 min** | Restore from autobackup |

## 🔢 Sizing /mnt/rman_bck

Dla PRIM ~ 50 GB datafiles + 1 GB redo/h, retention 14 dni:

| Typ | Częstotliwość | Rozmiar (skompresowany) | Retention | Razem |
|---|---|---|---|---|
| Full L0 | 1/tyg | ~25 GB | 4 tyg | **100 GB** |
| Incremental L1 | 6/tyg (Pn-Sb) | ~3 GB | 1 tyg | **18 GB** |
| Archivelog | 96/dzień (15 min) | ~250 MB/dzień | 14 dni | **3.5 GB** |
| Controlfile | autobkup | ~10 MB × 50 | overlay | **0.5 GB** |
| **Razem** | | | | **~125 GB** |

Shared folder `D:\_RMAN_BCK_from_Linux_` powinien mieć **min. 200 GB** (margines).

## 🎯 Walidacja polityki / Policy validation

```bash
# 1) Po setupie
rman target / catalog rman_cat/...@rcat01:1521/RCATPDB
RMAN> SHOW ALL;
# Powinno pokazac wszystkie CONFIGURE settings

# 2) Test backup ad-hoc
bash rman_full_backup.sh
# Sprawdz czas wykonania, rozmiar /mnt/rman_bck/full/

# 3) Test validate
bash rman_validate.sh
# Powinno byc czysto, bez 'failed' / 'corrupt'

# 4) Po pierwszej iteracji cyklu
sqlplus rman_cat/...@rcat01:1521/RCATPDB @sql/20_health_checks.sql
# Health check 1-6 daje obraz statusu
```

## 🚧 Troubleshooting

| Problem | Symptom | Rozwiazanie |
|---|---|---|
| `ORA-19809 limit exceeded for recovery files` | FRA pelne na PRIM | `rman_archivelog_only.sh` z DELETE ALL INPUT, lub zwieksz `db_recovery_file_dest_size` |
| Backup trwa >> spodziewane | I/O bottleneck na vboxsf | Zmniejsz PARALLELISM do 2, sprawdz host disk I/O |
| `RMAN-03002` w cron job | Cron env nie ma ORACLE_HOME | Skrypty maja `source ~/.bash_profile` |
| Crosscheck pokazuje EXPIRED | Pliki usuniete recznie z dysku | `DELETE EXPIRED` w `rman_crosscheck.sh` to czysci |
| Daily L1 nie ma od czego liczyc | Brak Level 0 | Najpierw FULL, potem L1 (skrypt to zaklada) |

## ⏭️ Nastepny krok / Next step

[07_ZDLRA_Like_Simulation.md](07_ZDLRA_Like_Simulation_PL.md) — Sprint 3: real-time redo + virtual full backup.
