# 📚 05 — Catalog Setup (Sprint 1, krok 3)

[![Sprint](https://img.shields.io/badge/Sprint-1-blue)]()
[![Step](https://img.shields.io/badge/Step-3_of_4-orange)]()
[![Component](https://img.shields.io/badge/Component-RMAN_Catalog-red)]()
[![Schema](https://img.shields.io/badge/Schema-rman__cat-purple)]()
[![Container](https://img.shields.io/badge/PDB-RCATPDB-darkgreen)]()

> 🎯 Tworzy schemat `rman_cat` w PDB RCATPDB, wykonuje `CREATE CATALOG`, rejestruje baze PRIM.

## 🧠 Co to jest RMAN Recovery Catalog?

[PL] Recovery Catalog to baza metadanych RMAN przechowujaca informacje o backupach **wielu** baz docelowych (TARGET).
Bez katalogu RMAN trzyma metadane tylko w controlfile - co ogranicza retention i historie. Z katalogiem mozemy:
- Trzymac historie backupow > 7 dni (controlfile cap)
- Centralnie zarzadzac backupami z wielu baz
- Uzywac stored scripts (CREATE SCRIPT)
- Robic raporty cross-database

[EN] RMAN catalog is a metadata DB storing backup info from many TARGET databases.
Benefits: long retention history, centralized management, stored scripts, cross-DB reports.

## 📋 Wymagania / Prerequisites

- ✅ rcat01 ma dzialajaca DB RCAT + PDB RCATPDB OPEN (Sprint 1 krok 2)
- ✅ Listener na rcat01:1521 zarejestrowal serwis RCATPDB
- ✅ Z prim01 sieciowo widoczny rcat01:1521

## 🚀 Metoda A — Automatyczna

```bash
# Na rcat01 jako oracle
ssh oracle@rcat01
bash /tmp/scripts/catalog_create.sh

# Z hosta (lub rcat01) - rejestracja PRIM
ssh oracle@rcat01 'bash /tmp/scripts/catalog_register_prim.sh'

# Z hosta (lub rcat01) - rejestracja STBY (CONFIGURE DB_UNIQUE_NAME + RESYNC)
# Pre-checks: DG broker SUCCESS, role prim01=PRIMARY/stby01=PHYSICAL STANDBY,
# TNS aliasy 'STBY' na prim01 i 'PRIM' na stby01, SSH equiv rcat01->prim01/stby01.
# Pre-checks: DG broker SUCCESS, roles prim01=PRIMARY/stby01=PHYSICAL STANDBY,
# TNS aliases 'STBY' on prim01 and 'PRIM' on stby01, SSH equiv rcat01->prim01/stby01.
ssh oracle@rcat01 'bash /tmp/scripts/catalog_register_stby.sh'
```

## 🛠️ Metoda B — Manualna (krok po kroku)

### B.1) Schemat rman_cat (na rcat01)

```bash
# Polacz sie do PDB RCATPDB jako sys.
# UWAGA: $LAB_PASS zawiera '!' - bash interpretuje jako history expansion.
# Uzyj single quotes wokol connect string LUB ${LAB_PASS} z double quotes.
# IMPORTANT: $LAB_PASS contains '!' - bash history expansion. Use single quotes or ${LAB_PASS}.
sqlplus "sys/${LAB_PASS}@rcat01:1521/RCATPDB" AS SYSDBA
```

```sql
-- DBCA dla 23ai/26ai NIE ustawia db_create_file_dest w PDB - musimy explicit
-- (lesson learned 2026-05-03 iter.9: bez tego CREATE TABLESPACE bez DATAFILE clause
-- zwraca ORA-02236 'invalid file name', a hardcoded path '/u02/oradata/RCAT/rcatpdb/'
-- zwraca ORA-01119 bo PDB jest w '/u02/oradata/RCAT/RCATPDB/' (uppercase)).
ALTER SYSTEM SET db_create_file_dest = '/u02/oradata' SCOPE=BOTH;

-- Tablespace dedykowany dla katalogu (Oracle Managed Files - bez DATAFILE clause).
-- Oracle umieszcza plik w /u02/oradata/RCAT/RCATPDB/datafile/o1_mf_<TS>_<HASH>_.dbf
CREATE TABLESPACE rcat_data
  DATAFILE SIZE 500M
  AUTOEXTEND ON NEXT 100M MAXSIZE 10G
  EXTENT MANAGEMENT LOCAL AUTOALLOCATE
  SEGMENT SPACE MANAGEMENT AUTO;

-- User wlasciciel katalogu (haslo z $LAB_PASS w /root/.lab_secrets)
CREATE USER rman_cat IDENTIFIED BY "<LAB_PASS_HERE>"
  DEFAULT TABLESPACE rcat_data
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON rcat_data;

-- Grants
GRANT CONNECT, RESOURCE TO rman_cat;
GRANT RECOVERY_CATALOG_OWNER TO rman_cat;

-- UWAGA: lesson learned 2026-05-04 iter.12 - w 26ai RECOVERY_CATALOG_OWNER NIE daje
-- automatycznie EXECUTE na DBMS_LOCK. Bez tego grantu RMAN failuje przy connect z
-- PLS-00201 'identifier DBMS_LOCK must be declared' (probuje wziac upgrade lock).
-- Skutek: BACKUP DATABASE PLUS ARCHIVELOG robi tylko archivelogi, samo DATABASE NIE.
GRANT EXECUTE ON SYS.DBMS_LOCK TO rman_cat;

EXIT
```

### B.2) CREATE CATALOG (przez RMAN)

```bash
# UWAGA: single quotes lub ${LAB_PASS} (bash '!' history expansion).
rman catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB"
```

```rman
RMAN> CREATE CATALOG;
Recovery catalog created.

RMAN> EXIT;
```

Pod spodem RMAN tworzy w 26ai/23ai:
- **~62 base tables** (catalog metadata: BACKUP_PIECE_DETAILS, DBINC, BACKUP_CORRUPTION...)
- **~124 widoki RCI_*** (RMAN Catalog Internal — wyzsze warstwy nad tabelami)
- **3 packages** (DBMS_RCVCAT, DBMS_RCVMAN_BACKUP, DBMS_RCVCAT_PRIV) + bodies + ~666 procedur/funkcji
- ~222 indexes, sequences, types

UWAGA: Lesson learned 2026-05-03 iter.9 — `CREATE CATALOG` NIE ma natywnego `IF NOT EXISTS`.
Re-run zwraca `RMAN-06441 already exists`. Jesli musisz przebudowac: `DROP CATALOG;` najpierw.

UWAGA: skrypty SQL dla RMAN uzywaja **`#` jako komentarz** (NIE `--` jak SQL!). PL/SQL nie dziala
w RMAN session - tylko RMAN commands + `SQL "..."` (uwaga: `SQL` wymaga TARGET database connection,
nie catalog). Walidacja schematu rman_cat musi byc OSOBNO przez sqlplus.

### B.3) REGISTER PRIM (na prim01)

```bash
ssh oracle@prim01
rman target / catalog rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB
```

```rman
RMAN> REGISTER DATABASE;
database registered in recovery catalog
starting full resync of recovery catalog
full resync complete

RMAN> RESYNC CATALOG;

RMAN> LIST DB_UNIQUE_NAME ALL;
RMAN> REPORT SCHEMA;
```

### B.4) REGISTER STBY (Data Guard standby)

[PL] Physical standby ma **TEN SAM DBID** co primary (DBID=229119773 dla nas), wiec NIE uzywamy `REGISTER DATABASE` na stby01 — zwroci `RMAN-20002 target database already registered`. Zamiast tego:
1. **Z PRIMARY** wykonujemy `CONFIGURE DB_UNIQUE_NAME 'STBY' CONNECT IDENTIFIER 'STBY'` — to dodaje STBY jako *site* w katalogu (`RC_SITE`).
2. **Ze STANDBY** wykonujemy `RESYNC CATALOG FROM DB_UNIQUE_NAME 'STBY'` — pobiera metadane z standby controlfile (LIST BACKUP/COPY widzi backupy zrobione na stby).

[EN] Physical standby shares the same DBID with primary, so we don't `REGISTER DATABASE` on stby. Instead: `CONFIGURE DB_UNIQUE_NAME` from primary, then `RESYNC CATALOG FROM DB_UNIQUE_NAME 'STBY'` from standby.

**Wzorzec / Pattern:**
```
PRIM (TARGET=PRIMARY) ──CONFIGURE DB_UNIQUE_NAME 'STBY' CONNECT IDENTIFIER 'STBY'──→ rcat01    # RC_SITE += STBY
STBY (TARGET=STANDBY) ──RESYNC CATALOG FROM DB_UNIQUE_NAME 'STBY'──→ rcat01                      # metadane z standby controlfile
```

> ⚠️ **Uwaga o rolach DG / DG role caveat:**
> `CONFIGURE DB_UNIQUE_NAME` wykonuje sie z **TARGET=baza w roli PRIMARY** (regardless of naming convention). W stanie po FSFO failover-ze role moga byc odwrocone — wtedy:
> - jesli prim01 (db_unique_name=PRIM) ma role STANDBY a stby01 (db_unique_name=STBY) ma role PRIMARY → najpierw zrob switchover do natural state (DGMGRL `SWITCHOVER TO PRIM`)
> - alternatywnie wykonaj komendy odwrotnie (TARGET=stby01, dodaj 'PRIM' jako standby) — ale to counterintuitive

#### B.4.1 — Pre-checks

```bash
# 1) DG broker SUCCESS, role spojne z nazwami
ssh infra01 "TNS_ADMIN=/etc/oracle/tns/obs_ext dgmgrl /@PRIM_ADMIN 'SHOW CONFIGURATION'"
# Oczekiwane: Configuration Status SUCCESS, prim01=primary, stby01=physical standby

# 2) TNS aliasy 'PRIM' i 'STBY' w tnsnames.ora na prim01 (i obu)
ssh oracle@prim01 'tnsping STBY'
# Oczekiwane: OK (XX msec)

# 3) APPLY-ON na stby01 (ze swiezo otwarta sesja shutdown moga byc APPLY-OFF)
ssh infra01 "TNS_ADMIN=/etc/oracle/tns/obs_ext dgmgrl /@PRIM_ADMIN 'EDIT DATABASE STBY SET STATE=APPLY-ON'"
```

#### B.4.2 — CONFIGURE DB_UNIQUE_NAME (z primary)

**Wariant 2a — przez plik SQL (zalecane):**

```bash
# Skopiuj plik na prim01 (lub uruchom z hosta z SSH equiv)
scp sql/04_register_stby.sql oracle@prim01:/tmp/

# Polacz sie i uruchom
ssh oracle@prim01
rman target / catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB" @/tmp/04_register_stby.sql
```

**Wariant 2b — interaktywnie (wpisywanie komend):**

```bash
ssh oracle@prim01
rman target / catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB"
```

```rman
# Dodaj STBY jako site w katalogu
RMAN> CONFIGURE DB_UNIQUE_NAME 'STBY' CONNECT IDENTIFIER 'STBY';

# Walidacja - powinno pokazac 2 sites: PRIM + STBY
RMAN> LIST DB_UNIQUE_NAME ALL;

RMAN> EXIT;
```

#### B.4.3 — RESYNC CATALOG FROM standby (na stby01)

**Wariant 3a — przez plik SQL (zalecane):**

```bash
# Skopiuj plik na stby01 (lub uruchom z hosta z SSH equiv)
scp sql/05_resync_stby.sql oracle@stby01:/tmp/

# Polacz sie i uruchom
ssh oracle@stby01
rman target / catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB" @/tmp/05_resync_stby.sql
```

**Wariant 3b — interaktywnie (wpisywanie komend):**

```bash
ssh oracle@stby01
rman target / catalog "rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB"
```

```rman
# Pobierz metadata standby controlfile do katalogu
RMAN> RESYNC CATALOG FROM DB_UNIQUE_NAME 'STBY';
starting full resync of recovery catalog
full resync complete

RMAN> EXIT;
```

#### B.4.4 — Walidacja STBY w katalogu (na rcat01)

> ⚠️ **Lesson learned 2026-05-04 iter.11:** w 26ai widok `RC_SITE` **NIE ma** kolumn `DBID` ani `DB_NAME` (tylko `SITE_KEY`, `DB_KEY`, `DATABASE_ROLE`, `DB_UNIQUE_NAME`). Trzeba JOIN do `RC_DATABASE` po `DB_KEY` aby pokazac DBID. ORA-00904 'invalid identifier' jesli probujesz `dbid` bezposrednio z `rc_site`.

```bash
sqlplus -S 'rman_cat/Oracle26ai_LAB!@rcat01:1521/RCATPDB' <<'SQL'
SET HEADING ON FEEDBACK OFF PAGESIZE 50 LINESIZE 150
COLUMN db_unique_name FORMAT A20 HEADING "DB Unique Name"
COLUMN database_role  FORMAT A18 HEADING "DG Role"
COLUMN db_name        FORMAT A12 HEADING "DB Name"
COLUMN dbid           FORMAT 99999999999 HEADING "DBID"

-- JOIN RC_SITE x RC_DATABASE: powinno zwrocic 2 sites z tym samym DBID
SELECT s.site_key, s.db_unique_name, s.database_role, d.name AS db_name, d.dbid
  FROM rc_site s
  JOIN rc_database d ON s.db_key = d.db_key
 ORDER BY s.db_unique_name;
-- Oczekiwane:
-- SITE_KEY  DB_UNIQUE_NAME  DG_ROLE   DB_NAME  DBID
-- --------  --------------  --------  -------  ----------
--    3      PRIM            PRIMARY   PRIM     229119773
--    566    STBY            STANDBY   PRIM     229119773    <- TEN SAM DBID, INNY db_unique_name

EXIT
SQL
```

> 💡 **Dlaczego RC_DATABASE pokazuje 1 wiersz a RC_SITE 2?**
> `RC_DATABASE` jest grupowane po DBID (czyli per logiczna baza). `RC_SITE` rozroznia po `db_unique_name` (czyli per fizyczna instancja w DG configuration).

## ✅ Walidacja / Validation

```bash
# UWAGA: single quotes wokol connect string (bash '!' history expansion).
# IMPORTANT: single quotes around connect string (bash '!' history expansion).
sqlplus -S 'rman_cat/Oracle26ai_LAB!@rcat01:1521/RCATPDB' <<'SQL'
SET HEADING ON FEEDBACK OFF PAGESIZE 50

-- Czy katalog stworzony? Liczymy obiekty calego schematu rman_cat.
-- Lesson 2026-05-03 iter.9: w 26ai widoki maja prefix RCI_ (NIE RC_).
SELECT 'Tables: ' || COUNT(*) FROM user_tables;     -- ~62
SELECT 'Views: ' || COUNT(*) FROM user_views;       -- ~124 RCI_*
SELECT 'Total objects: ' || COUNT(*) FROM user_objects;   -- ~1100+

-- Sample widokow RCI_* (RMAN Catalog Internal - 26ai prefix)
SELECT view_name FROM user_views WHERE view_name LIKE 'RCI_%' AND ROWNUM <= 5;
-- RCI_BACKUP_CONTROLFILE, RCI_BACKUP_DATAFILE, RCI_DATABASE...

-- Czy PRIM zarejestrowany? (po REGISTER DATABASE z PRIM)
SELECT name, dbid FROM rc_database;
-- Oczekiwane po B.3: 1 wiersz - PRIM widoczny z dbid (np. 229119773)
-- UWAGA: po B.4 (REGISTER STBY) RC_DATABASE wciaz pokaze 1 wiersz (grupowanie po DBID)
-- aby widziec oba (PRIM + STBY) uzyj RC_SITE - patrz B.4.4

-- Po B.4: RC_SITE powinno pokazac PRIM + STBY (same DBID, rozne db_unique_name)
-- UWAGA: RC_SITE w 26ai NIE ma DBID/DB_NAME - JOIN do RC_DATABASE po DB_KEY (lesson iter.11)
SELECT s.db_unique_name, s.database_role, d.name AS db_name, d.dbid
  FROM rc_site s
  JOIN rc_database d ON s.db_key = d.db_key
 ORDER BY s.db_unique_name;
-- Oczekiwane po B.4: 2 wiersze (PRIM + STBY) z tym samym DBID

EXIT
SQL
```

## 🔐 Bezpieczenstwo / Security

| Kwestia [PL] | Implementacja w LAB | W produkcji |
|---|---|---|
| Haslo rman_cat | `$LAB_PASS` z `/root/.lab_secrets` (chmod 600, kickstart-managed) | Oracle Wallet / JCEKS |
| Polaczenie sieciowe | Plain TCP/1521 | TCPS (SSL) |
| User RECOVERY_CATALOG_OWNER | Pelen dostep do katalogu | OK (to standard) |
| Backup hasla rman_cat | `/root/.lab_secrets` chmod 600 (manual) | Wallet + auto-rotate |

## 📦 Co dalej daje katalog

### Rozszerzone retention (vs controlfile-only)

```sql
-- Controlfile RECORD_KEEP_TIME (default 7 dni)
ALTER SYSTEM SET CONTROL_FILE_RECORD_KEEP_TIME=14 SCOPE=BOTH;
-- Po wygasnieciu RMAN traci metadane jesli nie ma katalogu

-- Z katalogiem trzymamy metadane tak dlugo jak chcemy (DBA decision)
CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 90 DAYS;  -- na PRIM
```

### Stored Scripts (centralne procedury)

```rman
RMAN> CREATE SCRIPT weekly_full_backup
{
  BACKUP DATABASE
    PLUS ARCHIVELOG
    DELETE INPUT
    TAG 'weekly_l0'
    FORMAT '/mnt/rman_bck/full/full_%U';
};

-- Z dowolnego klienta
RMAN> RUN { EXECUTE SCRIPT weekly_full_backup; }
```

### Cross-database reports

```sql
-- Backupy ze wszystkich zarejestrowanych baz
SELECT db_name, backup_type, count(*), sum(bytes)/1024/1024 AS size_mb
  FROM rc_backup_set
  GROUP BY db_name, backup_type
  ORDER BY 1, 2;
```

## 🚧 Troubleshooting

| Problem | Rozwiazanie |
|---|---|
| `RMAN-04004 connection error` | Sprawdz `tnsping rcat01:1521/RCATPDB` z PRIM |
| `RMAN-20002 target database already registered` | OK - juz zrobione, mozna `UNREGISTER DATABASE` i `REGISTER` ponownie |
| `ORA-12541 TNS:no listener` | `lsnrctl status` na rcat01, sprawdz czy listener dziala |
| `ORA-01017 invalid username/password` | Hasło `rman_cat` source-of-truth: `01_create_catalog_schema.sql` |
| Service RCATPDB nie widoczny | `ALTER SYSTEM REGISTER;` w RCATPDB jako sys |

## ⏭️ Nastepny krok / Next step

Sprint 1 ZAKONCZONY (kroki 1-3 + 3a REGISTER PRIM + 3b REGISTER STBY).

[PL] **Etapy Sprintu 1:** VM Preparation → DB Install + Auto-Start → Catalog Setup → REGISTER PRIM (Iter.10) → REGISTER STBY (Iter.11).

[EN] **Sprint 1 stages:** VM Preparation → DB Install + Auto-Start → Catalog Setup → REGISTER PRIM (Iter.10) → REGISTER STBY (Iter.11).

Przejdz do Sprintu 2:

[06_Backup_Policy.md](06_Backup_Policy_PL.md) — polityka backupowa (full/incremental/archivelog cycles).
