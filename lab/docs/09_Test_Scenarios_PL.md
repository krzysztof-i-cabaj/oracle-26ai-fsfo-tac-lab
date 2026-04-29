> [🇬🇧 English](./09_Test_Scenarios.md) | 🇵🇱 Polski

# 09 — Scenariusze Testowe FSFO i TAC (VMs2-install)

> **Cel:** Systematycznie przećwiczyć 6 scenariuszy demonstrujących Maximum Availability w Oracle 26ai:
> 1. Planowany switchover (PRIM ↔ STBY).
> 2. Nieplanowany failover (kill primary z FSFO).
> 3. TAC replay w trakcie transakcji.
> 4. Apply lag exceeded (FSFO blocked).
> 5. Awaria Master Observera (multi-Observer redundancja).
> 6. Walidacja readiness (`validate_env.sh`).

> **Prereq:** dokumenty 01–08 ukończone, FSFO `SYNCHRONIZED`, `MYAPP_TAC` aktywny, multi-Observer skonfigurowany (Master + 2 Backup), `TestHarness` skompilowany na `client01`.

---

## 0. Pre-flight przed scenariuszami

### 0.1. Walidacja środowiska

```bash
# Z prim01 jako oracle
bash /tmp/scripts/validate_env.sh --full
# Wszystkie statusy PASS = środowisko gotowe. FAIL = napraw zanim zaczniesz.
```

### 0.2. Server-side checklist (7 punktów)

```bash
# 1. Service MYAPP_TAC z poprawnymi atrybutami TAC (F-02)
ssh oracle@prim01 ". ~/.bash_profile && srvctl config service -db PRIM -service MYAPP_TAC | \
   grep -E 'Failover|Commit|Session State|Retention|Replay|Drain|Pluggable'"
# Oczekiwane:
#   Pluggable database name: APPPDB
#   Failover type: TRANSACTION
#   Failover restore: LEVEL1                     ← F-02
#   Commit Outcome: true
#   Session State Consistency: DYNAMIC
#   Retention: 86400 seconds
#   Replay Initiation Time: 1800 seconds
#   Drain timeout: 300 seconds
#   Notification: TRUE

# 2. ONS na stby01 chodzi pod systemd (F-13)
ssh root@stby01 "systemctl is-active oracle-ons.service && ss -ntlp | grep ':6[12]00'"
# Oczekiwane: 'active' + LISTEN *:6200 i 127.0.0.1:6100

# 3. Cross-site ONS na PRIM RAC
ssh grid@prim01 ". ~/.bash_profile && srvctl config ons | grep -i remote"
# Remote port: 6200

# 4. Broker SUCCESS + FSFO ENABLED (z infra01 - wallet tylko tu)
ssh oracle@infra01 "dgmgrl -silent /@PRIM_ADMIN 'SHOW CONFIGURATION'" | tr '\n' ' ' | \
   grep -oE "Configuration Status:[[:space:]]*\w+|Fast-Start Failover:[[:space:]]*\w+"
# Configuration Status: SUCCESS
# Fast-Start Failover: ENABLED

# 5. Multi-Observer aktywny (Master + 2 Backup)
ssh oracle@infra01 "dgmgrl -silent /@PRIM_ADMIN 'SHOW OBSERVERS'" | grep -E "obs_(ext|dc|dr)"
# obs_ext - Master    (infra01)
# obs_dc  - Backup    (prim01)
# obs_dr  - Backup    (stby01)

# 6. STBY w trybie Active Data Guard: OPEN READ ONLY WITH APPLY + PDB READ ONLY
ssh oracle@stby01 ". ~/.bash_profile && sqlplus -s / as sysdba <<'EOF'
SET PAGESIZE 0 FEEDBACK OFF
SELECT 'CDB / ' || open_mode FROM v\$database;
SELECT name || ' / ' || open_mode FROM v\$pdbs WHERE name <> 'PDB\$SEED';
EXIT
EOF"
# Oczekiwane / Expected:
#   CDB    / READ ONLY WITH APPLY     ← Real-Time Query Active DG
#   APPPDB / READ ONLY                ← PDB w trybie czytania
# Jeśli CDB=MOUNTED lub PDB=MOUNTED → SAVE STATE rozjechał się
# z apply (rzadkie, sekcja 0.3 fallback).

# 6.a. Oracle Restart startoption (po reboot stby01 ma OPEN RO automatycznie)
ssh oracle@stby01 "srvctl config database -db STBY | grep -E 'Start option|Open mode'"
# Oczekiwane: Start option: read only (NIE 'mount')

# 7. Klient TestHarness gotowy na client01
ssh oracle@client01 "ls -la /opt/lab/src/TestHarness.class /opt/lab/jars/*.jar | wc -l"
# >= 6 plików (TestHarness.class + 5 jarów)

# 8. Serwis MYAPP_TAC zarejestrowany w Oracle Restart na stby01 (KLUCZOWE dla auto-start po failover!)
ssh oracle@stby01 ". ~/.bash_profile && srvctl config service -db STBY -service MYAPP_TAC | \
   grep -E 'Service role|Failover type|Failover restore'"
# Oczekiwane:
#   Service role: PRIMARY                ← serwis aktywuje się tylko gdy STBY zostanie PRIMARY
#   Failover type: TRANSACTION
#   Failover restore: LEVEL1
# Brak output / "PRCD-1014" = serwis nie zarejestrowany w Oracle Restart.
# Naprawa: ssh oracle@stby01 'bash /tmp/scripts/setup_tac_services_stby.sh'
# Bez tego po failover trzeba ręcznie tac_service_resume.sh (FIX-095 fallback).
```

### 0.3. Fallback dla STBY w MOUNTED (rzadkie — gdy SAVE STATE się rozjedzie)

> **W zalecanej konfiguracji ten krok nie jest potrzebny.** `create_standby_broker.sh` wykonuje `ALTER PLUGGABLE DATABASE ALL SAVE STATE` po stworzeniu STBY oraz `srvctl modify database -startoption "READ ONLY"`, więc po każdym `STARTUP`/reboot stby01 baza i PDB-y otwierają się automatycznie w `READ ONLY WITH APPLY` (Real-Time Query Active DG).
>
> Workaround poniżej jest potrzebny **tylko** gdy:
> - `create_standby_broker.sh` nie zostało uruchomione w pełni (manualny path z docs/06 — sprawdź czy wykonano sekcję Active DG),
> - lub po manualnym `STARTUP NOMOUNT` / `STARTUP MOUNT` (np. po RMAN restore) — wtedy stan SAVE STATE nie jest aplikowany dopóki nie otworzysz PDB ponownie i nie zapiszesz stanu.

```bash
# 1. Broker APPLY-OFF (z infra01)
ssh oracle@infra01 "dgmgrl -silent /@PRIM_ADMIN 'EDIT DATABASE stby SET STATE=APPLY-OFF'"

# 2. Otwórz CDB + PDB w READ ONLY i ZAPISZ stan (przeżyje kolejny STARTUP)
ssh oracle@stby01 ". ~/.bash_profile && sqlplus -s / as sysdba <<EOF
ALTER DATABASE OPEN READ ONLY;
ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY;
ALTER PLUGGABLE DATABASE ALL SAVE STATE;
EXIT
EOF"

# 3. Oracle Restart startoption (idempotent — robimy by mieć pewność)
ssh oracle@stby01 "srvctl modify database -db STBY -startoption 'READ ONLY'"

# 4. Broker APPLY-ON — wracamy do Real-Time Query
ssh oracle@infra01 "dgmgrl -silent /@PRIM_ADMIN 'EDIT DATABASE stby SET STATE=APPLY-ON'"
```

### 0.4. Pułapki które będą się powtarzać

> 💡 **Wallet location:** wallet auto-login `/etc/oracle/wallet/obs_*` jest **na każdym hoście z Observerem** (infra01: `obs_ext`, prim01: `obs_dc`, stby01: `obs_dr`). Connect przez alias bez hasła (`/@PRIM_ADMIN`, `/@STBY_ADMIN`) działa **tylko z hosta gdzie jest wallet**. Z `client01` (bez Observera) trzeba albo SSH na hosta z wallet'em, albo użyć explicit hasła `sys/Oracle26ai_LAB!@PRIM_ADMIN`.
>
> 💡 **dgmgrl multiline grep:** komendy `SHOW CONFIGURATION` / `SHOW FAST_START FAILOVER` w 26ai zwracają **multi-line output**. Plain `grep PATTERN` może zwrócić 0 trafień nawet jeśli pattern jest w outputcie. Użyj `tr '\n' ' '` flatten przed grep:
> ```bash
> dgmgrl -silent /@PRIM_ADMIN 'SHOW CONFIGURATION' | tr '\n' ' ' | grep -oE "Status:[[:space:]]*\w+"
> ```
>
> 💡 **TestHarness uruchomiony helperem:** ścieżka `/tmp/src/TestHarness.java` po kompilacji (`javac`) na client01. Wszystkie poniższe scenariusze używają polecenia uruchamiającego TestHarness w tle:
> ```bash
> # Skrót używany w scenariuszach (Java 17 wymaga --add-opens, F-09):
> ssh oracle@client01 'cd /opt/lab/src && \
>     java --add-opens=java.base/java.lang=ALL-UNNAMED \
>          --add-opens=java.base/java.util=ALL-UNNAMED \
>          --add-opens=java.base/jdk.internal.misc=ALL-UNNAMED \
>          --add-opens=java.base/sun.nio.ch=ALL-UNNAMED \
>          -cp "/opt/lab/jars/*:." TestHarness' &
> ```
> APP_PASSWORD nie wymaga ustawienia — TestHarness ma fallback do `Oracle26ai_LAB!` (konwencja labu).

---

## Scenariusz 1 — Planowany switchover (PRIM → STBY → PRIM)

### Cel
Zademonstrować planowe przełączenie roli Primary na Standby (i z powrotem) **bez utraty danych** i z minimalnym downtime aplikacji.

### Kroki

**1. Uruchom `TestHarness` w tle na `client01`** (helper z sekcji 0.4).

**2. Z `infra01` wykonaj walidację i switchover:**
```bash
ssh oracle@infra01
dgmgrl /@PRIM_ADMIN
```
```text
DGMGRL> SHOW CONFIGURATION;
   Configuration Status:  SUCCESS
   Fast-Start Failover:   ENABLED
   Protection Mode:       MaxAvailability

DGMGRL> VALIDATE DATABASE STBY;
   Database Role:           physical standby database
   Ready for Switchover:    Yes
   Ready for Failover:      Yes (Primary Running)

DGMGRL> SWITCHOVER TO STBY;
   Performing switchover NOW, please wait...
   New primary database "STBY" is opening...
   Switchover succeeded, new primary is "STBY"

DGMGRL> SHOW CONFIGURATION;
   Members:
     STBY - Primary database              ← teraz primary
       PRIM - Physical standby database   ← teraz standby
   Configuration Status: SUCCESS
```

**3. W konsoli `TestHarness` zobaczysz drain + reconnect:**
```
[54] SUKCES: PRIM1  SID=456  rows=1
[55] RECOVERABLE (TAC replay/failover): 1089 - ORA-01089: immediate shutdown
[56] RECOVERABLE (TAC replay/failover): 3113 - ORA-03113: end-of-file
[57] SUKCES: STBY  SID=123  rows=1   ← klient już łączy się do STBY
```

> ⚠ **Service start na nowym primary (stby01) — Oracle Restart vs fallback.** Stby01 ma **Grid Infrastructure for a Standalone Server (Oracle Restart)**, więc CRS na poziomie hosta automatycznie startuje bazę i jej serwisy.
>
> **Stan zalecany (jeśli wykonano `setup_tac_services_stby.sh` / docs/08 Krok 1.5):**
> Serwis `MYAPP_TAC` jest zarejestrowany w Oracle Restart na stby01 z `-role PRIMARY`. Po promote CRS sam go startuje w 5–15 s. Sprawdź:
> ```bash
> ssh oracle@stby01 ". ~/.bash_profile && srvctl status service -db STBY -service MYAPP_TAC"
> # Service MYAPP_TAC is running on database STBY    ← OK, nic nie trzeba robić
> ```
>
> **Fallback (FIX-095) — gdy serwis NIE wystartował automatycznie** (np. krok 1.5 z docs/08 nie został wykonany lub Oracle Restart ma problem):
> ```bash
> ssh oracle@stby01 ". ~/.bash_profile && bash /tmp/scripts/tac_service_resume.sh"
> # Helper sprawdzi role + serwis, w razie potrzeby DBMS_SERVICE.START_SERVICE.
> ```
> Pułapki nazwy: `'MYAPP_TAC'` → ORA-44773 (case); `'myapp_tac.lab.local'` → ORA-44304 (domain). Tylko `'myapp_tac'` lowercase. Helper używa poprawnej formy.
>
> Switchover w drugą stronę (`STBY → PRIM`): Grid CRS na prim01/02 startuje serwis bez ingerencji — analogicznie jak Oracle Restart na stby01 dla kierunku PRIM→STBY.

**4. Switchover z powrotem:**
```text
DGMGRL> SWITCHOVER TO PRIM;
```

> ✅ **Active Data Guard zachowuje stan po SWITCHOVER TO PRIM.** Z poprawnie wykonanym `create_standby_broker.sh` (lub manual sekcja Active DG w docs/06):
> - `srvctl modify database -db STBY -startoption "READ ONLY"` → po `STARTUP` Oracle Restart sam otwiera w READ ONLY,
> - `ALTER PLUGGABLE DATABASE ALL SAVE STATE` → PDB-y wracają do `READ ONLY` po każdym STARTUP,
>
> więc po `SWITCHOVER TO PRIM` baza STBY (jako nowy standby) otwiera się od razu w `READ ONLY WITH APPLY` — bez ręcznego `STARTUP MOUNT` ani manualnego `OPEN READ ONLY`.
>
> ⚠ **Fallback (sekcja 0.3)** — wymagany tylko jeśli broker mimo wszystko poprosi:
> ```
> Please complete the following steps to finish switchover:
>   start up instance "STBY" of database "stby"
> ```
> Wtedy patrz sekcja 0.3 (APPLY-OFF → OPEN RO + SAVE STATE → APPLY-ON). To rzadkie — typowo po manualnym `STARTUP NOMOUNT` lub gdy ktoś zatrzymał DB przed save_state został zaaplikowany.

### Weryfikacja
- `SHOW CONFIGURATION` → `SUCCESS` i `PRIM = Primary database`
- `app_user.test_log` zawiera ciągłe wpisy bez luk (`SELECT COUNT(*) FROM app_user.test_log` rośnie monotonnicznie)
- Apply lag = 0

### Oczekiwany czas
| Kierunek | Switchover | Downtime aplikacji (Oracle Restart skonfigurowany) | Downtime (manual fallback) |
|----------|-----------|---------------------------------------------------|----------------------------|
| PRIM → STBY (na stby01) | 15–30 s (broker) | **~5–15 s** (Oracle Restart auto-start serwisu) | ~60 s (z `tac_service_resume.sh`) |
| STBY → PRIM (na prim01/02) | 15–30 s (broker) | **~5–15 s** (Grid CRS auto-start) | n/a (CRS zawsze działa) |

**Warunek "Oracle Restart skonfigurowany":** wykonano `setup_tac_services_stby.sh` (lub manual Krok 1.5 z docs/08) — sprawdź w pre-flight punkt 8.

---

## Scenariusz 2 — Nieplanowany failover z FSFO (kill primary)

### Cel
Zademonstrować **automatyczny** failover wykonany przez Observera po awarii Primary, bez interwencji człowieka.

### Kroki

**1. Zweryfikuj że FSFO jest "armed" (z `infra01`):**
```bash
ssh oracle@infra01 "dgmgrl -silent /@PRIM_ADMIN 'SHOW FAST_START FAILOVER'" | tr '\n' ' ' | \
   grep -oE "Threshold:[[:space:]]*[0-9]+|Target:[[:space:]]*\w+|Observer:[[:space:]]*\w+"
# Threshold: 30
# Target: STBY
# Observer: obs_ext

ssh oracle@infra01 'sqlplus -s /@PRIM_ADMIN as sysdba <<EOF
SELECT fs_failover_status FROM v$database;
EXIT
EOF'
# SYNCHRONIZED   ← gotowe do failover
```

**2. Uruchom `TestHarness` w tle na `client01`** (helper z 0.4).

**3. Zaznacz czas startu, zabij obie instancje PRIM:**
```bash
date
# Tue Apr 23 16:00:00 UTC 2026

# Najszybszy sposób — shutdown abort obu instancji równolegle.
ssh oracle@prim01 'sqlplus -s / as sysdba <<EOF
SHUTDOWN ABORT
EXIT
EOF' &
ssh oracle@prim02 'sqlplus -s / as sysdba <<EOF
SHUTDOWN ABORT
EXIT
EOF' &
wait

# Alternatywa "twardsza" — pełne zatrzymanie CRS na obu nodach
# (wyłącza też listenery/ASM — szerszy scope niż shutdown abort):
# ssh root@prim01 sudo /u01/app/23.26/grid/bin/crsctl stop crs -f
# ssh root@prim02 sudo /u01/app/23.26/grid/bin/crsctl stop crs -f
```

**4. Obserwuj log Observera — oczekiwany flow:**
```bash
ssh oracle@infra01 "tail -f /var/log/oracle/obs_ext/obs_ext.log"
```
```
[W000 ...] Unable to connect to primary database
[W000 ...] Primary has no observer
[W000 ...] Threshold not reached; observer retry 1/3
[W000 ...] Observer retry 2/3, delay 10 seconds
[W000 ...] Threshold reached; initiating failover                ← ~30 s od kill
[W000 ...] Failover to STBY begun
[W000 ...] Failover succeeded; new primary is STBY               ← ~30–45 s
[W000 ...] Old primary needs to be reinstated
```

**5. Zmierz czas end-to-end:**
```bash
ssh oracle@infra01 'sqlplus -s /@STBY_ADMIN as sysdba <<EOF
SELECT database_role FROM v$database;
EXIT
EOF'
# DATABASE_ROLE
# PRIMARY

date
# Tue Apr 23 16:00:42 UTC 2026     ← ~42 s od shutdown abort
```

**6. Sprawdź serwis na nowym primary (Oracle Restart powinien sam wystartować):**
```bash
# Stan oczekiwany: Oracle Restart na stby01 wystartował serwis automatycznie
# (jeśli wykonano docs/08 Krok 1.5 / setup_tac_services_stby.sh).
ssh oracle@stby01 ". ~/.bash_profile && srvctl status service -db STBY -service MYAPP_TAC"
# Service MYAPP_TAC is running on database STBY    ← klient TAC replay zadziała

# Fallback (FIX-095) — TYLKO jeśli powyższe pokazuje "is not running":
ssh oracle@stby01 ". ~/.bash_profile && bash /tmp/scripts/tac_service_resume.sh"
```

**7. W `TestHarness` widać:**
```
[67] SUKCES: PRIM2  SID=456  rows=1                  ← ostatni przed awarią
[68] RECOVERABLE (TAC replay/failover): 3113 - ORA-03113: end-of-file
[69] RECOVERABLE (TAC replay/failover): 17008 - Closed Connection
[70] SUKCES: STBY  SID=234  rows=1                   ← pierwsza po failover (~60 s)
```

### Weryfikacja
- End-to-end failover broker: **30–45 s**
- Total downtime klienta z manual `tac_service_resume.sh`: **~60 s**
- **0 utraconych transakcji** (commit_outcome + replay)
- `v$database.database_role` na STBY = `PRIMARY`
- Broker configuration = `SUCCESS`
- `SELECT COUNT(*) FROM app_user.test_log` ciągłe (każdy `loop=N` zapisany)

### Reinstate starego Primary

```bash
# 1. Uruchom prim01/prim02 (jeśli były wyłączone z prądu — power on; jeśli tylko shutdown abort — pomiń tę linię)
# 2. CRS na obu nodach
ssh root@prim01 '/u01/app/23.26/grid/bin/crsctl start crs'
ssh root@prim02 '/u01/app/23.26/grid/bin/crsctl start crs'
sleep 120

# 3. Broker auto-reinstate (Flashback) — z infra01
ssh oracle@infra01
dgmgrl /@STBY_ADMIN
```
```text
DGMGRL> SHOW CONFIGURATION;
   PRIM - Physical standby database (reinstate required)

# Po 60–120 s:
DGMGRL> SHOW CONFIGURATION;
   Configuration Status: SUCCESS
   PRIM - Physical standby database     ← reinstated
```

Opcjonalnie switchover z powrotem do oryginalnego primary:
```text
DGMGRL> SWITCHOVER TO PRIM;
```
(uwaga FIX-094 — sekcja 0.3, jeśli broker poprosi o STARTUP MOUNT + OPEN RO).

---

## Scenariusz 3 — TAC replay w trakcie transakcji (kill server process)

### Cel
Zademonstrować że TAC z `session_state=DYNAMIC`, `commit_outcome=TRUE`, `failover_restore=LEVEL1` **automatycznie odtwarza** dłuższą transakcję gdy server process jest zabity w połowie.

### Kroki

**1. Tymczasowa modyfikacja `TestHarness.java` na batch transakcję:**

Zmień główną pętlę: zamiast pojedynczego INSERT/COMMIT — 50× INSERT z 1-sekundowym sleep, jeden COMMIT na końcu (długość transakcji ~50 s):

```java
try (Connection conn = pds.getConnection()) {
    conn.setAutoCommit(false);   // F-09 — UCP 23.x default=true bez setAutoCommit dałby ORA-17273
    for (int i = 0; i < 50; i++) {
        try (PreparedStatement ps = conn.prepareStatement(
                "INSERT INTO app_user.test_log (instance, session_id, message) VALUES (?, ?, ?)")) {
            ps.setString(1, "batch-" + i);
            ps.setInt(2, (int)loop);
            ps.setString(3, "Batch entry " + i);
            ps.executeUpdate();
        }
        Thread.sleep(1000);
    }
    conn.commit();
    System.out.println("[" + loop + "] BATCH COMMITTED 50 rows");
}
```

Rekompilacja i start:
```bash
ssh oracle@client01
cd /opt/lab/src
javac -cp "/opt/lab/jars/*" TestHarness.java
java --add-opens=java.base/java.lang=ALL-UNNAMED \
     --add-opens=java.base/java.util=ALL-UNNAMED \
     --add-opens=java.base/jdk.internal.misc=ALL-UNNAMED \
     --add-opens=java.base/sun.nio.ch=ALL-UNNAMED \
     -cp '/opt/lab/jars/*:.' TestHarness
```

**2. Podczas trwającego batch-a — zabij server process klienta:**

Znajdź właściwy SPID (server foreground powiązany z sesją JDBC przez serwis `MYAPP_TAC`):
```bash
ssh oracle@prim01 ". ~/.bash_profile && sqlplus -s / as sysdba <<EOF
SET PAGESIZE 50 LINESIZE 200
COL spid     FORMAT A10
COL program  FORMAT A30
COL sid_ser  FORMAT A14
SELECT s.sid || ',' || s.serial# AS sid_ser, s.program, p.spid, s.service_name
FROM   gv\$session s JOIN gv\$process p ON s.paddr = p.addr
WHERE  s.service_name LIKE 'myapp_tac%'
   AND s.program LIKE 'JDBC%';
EXIT
EOF"
# Wybierz SPID z output i zabij konkretnie ten proces:
ssh oracle@prim01 "kill -9 <SPID>"
```

> 💡 **Dlaczego konkretny SPID, nie SMON/PMON:** zabicie BACKGROUND process (PMON/SMON/LGWR) zinstancjonuje całą instancję — pokaże się reconnect do drugiego node-a RAC, nie czysty replay TAC. **Server foreground process** (oznaczony `(LOCAL=NO)`) powiązany z konkretną sesją JDBC daje czystą demonstrację replay.

**3. Oczekiwany output `TestHarness`:**
```
Batch 22 inserted...
Batch 23 inserted...
Batch 24 inserted...
[loop=N] RECOVERABLE (TAC replay/failover): 3113 - ORA-03113: end-of-file on communication channel
   (Application Continuity replayed 24 statements successfully)
Batch 25 inserted...
Batch 26 inserted...
...
[loop=N] BATCH COMMITTED 50 rows
```

Oracle JDBC TAC zapisał **LTXID** przed każdym INSERT, wykrył rozłączenie (server proc kill = TCP RST), automatycznie otworzył nową sesję (na innej instancji RAC po FAN event) i **odtworzył** 24 INSERT-y od ostatniego committed point (`failover_restore=LEVEL1`), kontynuując od miejsca przerwania.

### Weryfikacja
**Brak duplikatów w `test_log`:**
```sql
SELECT COUNT(*) FROM app_user.test_log WHERE session_id = <nr_loop>;
-- 50 (dokładnie, NIE 74 = 24+50)
```
**Bez wyjątku do użytkownika końcowego** — TestHarness złapał `SQLRecoverableException` (w F-09 osobny handler), TAC samo zrobiło replay, transakcja committed.

---

## Scenariusz 4 — Apply lag exceeded (FSFO blocked, Zero Data Loss)

### Cel
Zademonstrować że gdy apply lag standby przekracza `FastStartFailoverLagLimit` (w naszej konfiguracji = 0), FSFO **NIE wykonuje** automatycznego failover — chroniąc przed split-brain i utratą danych.

### Kroki

**1. Sprawdź apply lag (powinien być 0):**
```bash
ssh oracle@infra01 'sqlplus -s /@PRIM_ADMIN as sysdba <<EOF
SELECT name, value FROM v$dataguard_stats;
EXIT
EOF'
# apply lag       0 00:00:00
```

**2. Zatrzymaj MRP na STBY (z `infra01`):**
```bash
ssh oracle@infra01 'sqlplus -s /@STBY_ADMIN as sysdba <<EOF
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
EXIT
EOF'
```

**3. Na PRIM wymuś archiving + obciążenie redo:**
```bash
ssh oracle@prim01 'sqlplus -s / as sysdba <<EOF
BEGIN
    FOR i IN 1..10 LOOP
        EXECUTE IMMEDIATE '"'"'ALTER SYSTEM SWITCH LOGFILE'"'"';
        DBMS_SESSION.SLEEP(5);
    END LOOP;
END;
/
EXIT
EOF'
```

**4. Apply lag rośnie — Observer raportuje zablokowanie FSFO:**
```bash
ssh oracle@infra01 "tail -f /var/log/oracle/obs_ext/obs_ext.log"
```
```
[W000 ...] Standby STBY is 45 seconds behind primary
[W000 ...] FSFO is not ready to failover — standby not synchronized
```

**5. Spróbuj wymusić awarię primary — Observer NIE wykona failover:**
```bash
ssh oracle@infra01 "dgmgrl -silent /@PRIM_ADMIN 'SHOW CONFIGURATION'"
# FS Failover Status: NOT SYNCHRONIZED   ← blokada

# Symulacja awarii (równolegle):
ssh oracle@prim01 'sqlplus -s / as sysdba <<<"SHUTDOWN ABORT"' &
ssh oracle@prim02 'sqlplus -s / as sysdba <<<"SHUTDOWN ABORT"' &
wait

# Observer w logu wyświetli:
#   "Threshold reached but apply lag exceeds LagLimit - failover blocked"
# = mechanizm zachował integralność, nie poświęcił danych w imię dostępności.
```

**6. Wznów apply, FSFO wraca do SYNCHRONIZED:**
```bash
# Najpierw uruchom prim01/02 z powrotem.
ssh root@prim01 '/u01/app/23.26/grid/bin/crsctl start crs'
ssh root@prim02 '/u01/app/23.26/grid/bin/crsctl start crs'
sleep 120

ssh oracle@infra01 'sqlplus -s /@STBY_ADMIN as sysdba <<EOF
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT;
EXIT
EOF'

# Po chwili
ssh oracle@infra01 'sqlplus -s /@PRIM_ADMIN as sysdba <<EOF
SELECT fs_failover_status FROM v$database;
EXIT
EOF'
# SYNCHRONIZED
```

> 💡 **Tryby FSFO (F-22):**
> - `LagLimit=0` + Protection Mode `MaxAvailability` (SYNC) = **Zero Data Loss Mode**. Failover blokowany przy każdym apply lag > 0.
> - `LagLimit=30` + Protection Mode `MaxPerformance` (ASYNC) = **Potential Data Loss Mode**. Failover akceptuje stratę do 30 s redo. Zalecane gdy łącze do standby jest wolne i SYNC by spowolnił commit na primary.
> - Konfiguracja LAB-u używa **Zero Data Loss Mode** — Scenariusz 4 demonstruje skutek tej decyzji.

---

## Scenariusz 5 — Awaria Master Observera (multi-Observer redundancja)

### Cel
Zweryfikować że awaria `infra01` (Master Observer `obs_ext`) **nie wyłącza** mechanizmu FSFO — Backup Observer (`obs_dc` na prim01 lub `obs_dr` na stby01) automatycznie przejmuje rolę Active.

### Wymagania wstępne
Multi-Observer wdrożony zgodnie z `07_FSFO_Observers_PL.md` sekcja 6:
```bash
dgmgrl /@PRIM_ADMIN "SHOW OBSERVERS;"
# Master + 2 Backup
```

### Kroki

**1. Zatrzymaj Master Observera:**
```bash
ssh root@infra01 "systemctl stop dgmgrl-observer-obs_ext"
```

**2. Obserwuj promote (z prim01 lub stby01, np.):**
```bash
for i in 1 2 3 4 5 6; do
    ssh oracle@prim01 ". ~/.bash_profile && dgmgrl -silent /@PRIM_ADMIN 'SHOW OBSERVERS'" | grep -E "Master|Backup"
    sleep 10
done
# W ciągu 10–60 s widzisz: jeden z Backup zmienia status na Master.
```

**3. Weryfikacja gotowości FSFO:**
```bash
ssh oracle@prim01 ". ~/.bash_profile && dgmgrl -silent /@PRIM_ADMIN 'SHOW FAST_START FAILOVER'"
# Fast-Start Failover: ENABLED   ← system nadal zbrojny
```

**4. (opcjonalnie) Wyzwól failover z ubitym Master Observerem:**

Powtórz Scenariusz 2 punkty 3–6, ale **bez restartu obs_ext**. Backup Observer wykona failover i `tac_service_resume.sh` na nowym primary musi być uruchomiony tak samo jak w scenariuszu 2.

**5. Restore Master:**
```bash
ssh root@infra01 "systemctl start dgmgrl-observer-obs_ext"
ssh oracle@infra01 "dgmgrl -silent /@PRIM_ADMIN 'SHOW OBSERVERS'"
# obs_ext wraca jako Backup; obecny Active pozostaje aktywny aż padnie.
```

### Weryfikacja
- Promote Backup → Master w czasie < 60 s.
- `SHOW FAST_START FAILOVER` przez cały czas `ENABLED`.
- W przypadku scenariusza 5.4 (failover z obs_ext padłym): RTO + downtime klienta jak w scenariuszu 2 (`~60 s`).

---

## Scenariusz 6 — Walidacja readiness (`validate_env.sh`)

### Cel
Użyć skryptu `validate_env.sh` do kompleksowej walidacji konfiguracji **przed** scenariuszami 1–5 oraz **po** każdym z nich (wykrywanie regresji w środowisku).

### Kroki

**1. Pre-flight check (przed scenariuszami):**
```bash
ssh oracle@prim01 "bash /tmp/scripts/validate_env.sh --full"
```
Oczekiwane: wszystkie 10 sekcji z PASS, exit code 0.

**2. Pełna walidacja TAC (na poziomie SQL, dodatkowo):**
```bash
ssh oracle@prim01 ". ~/.bash_profile && sqlplus -s / as sysdba @/tmp/sql/tac_full_readiness_26ai.sql > /tmp/tac_readiness.log"
grep -E "PASS|FAIL|WARN" /tmp/tac_readiness.log | sort | uniq -c | sort -rn
# Powinno: 0 FAIL, dopuszczalne pojedyncze WARN (np. retention_timeout < 86400 - reco only).
```

**3. Po failoverze (Scenariusz 2) — sprawdź czy serwis kompletny na nowym primary:**
```bash
ssh oracle@stby01 ". ~/.bash_profile && sqlplus -s / as sysdba @/tmp/sql/tac_full_readiness_26ai.sql" | \
    grep -E "failover_restore|commit_outcome|session_state_consistency"
# Wszystkie PASS = środowisko po failover gotowe na replay.
```

**4. Monitor replay w trakcie testów Scenariusz 3:**
```bash
# W osobnym terminalu, na primary:
ssh oracle@prim01 ". ~/.bash_profile && sqlplus -s / as sysdba @/tmp/sql/tac_replay_monitor_26ai.sql"
# Pokaże: gv$replay_context (per-context metrics), gv$session.failed_over=YES count.
```

### Weryfikacja
- `validate_env.sh` exit code 0 (zero FAIL).
- `tac_full_readiness_26ai.sql` raport: `failover_restore=LEVEL1` (PASS), `commit_outcome` (PASS), `session_state_consistency=DYNAMIC` (PASS), `aq_ha_notifications=YES` (PASS).
- `tac_replay_monitor_26ai.sql` po Scenariuszu 3 pokazuje >= 1 `failed_over=YES` session.

---

## Podsumowanie — checklist po wszystkich testach

| # | Scenariusz | Oczekiwany wynik | RTO/downtime (Oracle Restart skonf.) | Walidacja po teście |
|---|-----------|-------------------|--------------------------------------|---------------------|
| 1 | Switchover PRIM→STBY→PRIM | broker SUCCESS, `test_log` ciągły | **~5–15 s** w obie strony (CRS auto-start) | `SHOW CONFIGURATION` SUCCESS |
| 2 | Unplanned failover (FSFO) | new primary STBY w 30–45 s, replay OK | **~30–45 s** (broker + Oracle Restart auto-start) | `database_role=PRIMARY` na STBY, broker SUCCESS |
| 3 | TAC replay (kill server proc) | `app_user.test_log` ma dokładnie 50 rows na batch (bez duplikatów) | brak (klient nie widzi błędu) | `tac_replay_monitor_26ai.sql` pokazuje failed_over |
| 4 | Apply lag exceeded | FSFO blokowane, `NOT SYNCHRONIZED`, baza nie staje się primary po awarii | manual recovery | `fs_failover_status=SYNCHRONIZED` po wznowieniu MRP |
| 5 | Awaria Master Observera | promote Backup w 10–60 s, FSFO ENABLED | brak | `SHOW OBSERVERS` pokazuje Master+Backup |
| 6 | Readiness validation | `validate_env.sh` exit 0, TAC readiness PASS | n/a | wszystkie sekcje PASS |

### Pełna sekwencja jednorazowa "smoke test" (rekomendowana)

```bash
# 1. Pre-flight
ssh oracle@prim01 "bash /tmp/scripts/validate_env.sh --full"          # exit 0

# 2. TestHarness w tle
ssh oracle@client01 "cd /opt/lab/src && /opt/lab/run_testharness.sh &"

# 3. Scenariusz 1 + reset
# (wykonaj dgmgrl SWITCHOVER + tac_service_resume + SWITCHOVER back + 0.3 fix)

# 4. Scenariusz 2 (najwazniejszy demo)
# (shutdown abort + obserwuj log + tac_service_resume + reinstate)

# 5. Scenariusz 3 (TAC replay z modyfikowanym TestHarness)

# 6. Scenariusz 5 (multi-Observer)

# 7. Final validation
ssh oracle@prim01 "sqlplus / as sysdba @/tmp/sql/tac_full_readiness_26ai.sql > /tmp/final.log"
ssh oracle@prim01 "grep -c FAIL /tmp/final.log"   # 0 = pass
```

Po przejściu wszystkich 6 scenariuszy środowisko jest udokumentowane jako zachowujące **Zero Data Loss + Application Transparency** w warunkach awarii. To jest kompletny dowód spełniania Maximum Availability Architecture (MAA) Oracle 26ai.

---

## Następne kroki / Powiązane dokumenty

- `10_Performance_Tuning.md` — pomiar wydajności: DBCA czas, fio IOPS, time drift count.
- `../scripts/tac_service_resume.sh` — helper post-failover (sekcje 1.3, 2.6).
- `../scripts/validate_env.sh` — readiness validation (sekcja 0.1, 6.1).
- `../sql/tac_full_readiness_26ai.sql` — szczegółowy SQL audit.
- `../sql/tac_replay_monitor_26ai.sql` — monitoring replay w runtime.

