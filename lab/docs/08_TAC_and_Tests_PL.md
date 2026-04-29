> [🇬🇧 English](./08_TAC_and_Tests.md) | 🇵🇱 Polski

# 08 — Transparent Application Continuity i Testy Niezawodności (VMs2-install)

> **Cel:** Uruchomienie na klastrze RAC serwisu aplikacyjnego przystosowanego do funkcji **Transparent Application Continuity (TAC)**. Skonfigurowanie powiadomień FAN (Fast Application Notification) poprzez usługę ONS pomiędzy klastrem a węzłem Standby. Na koniec: przygotowanie środowiska klienckiego (`client01`), uruchomienie aplikacji klienckiej w Javie (UCP) i przetestowanie zachowania sesji bazodanowych.

Dokument opisuje dwie metody konfiguracji serwisu i ONS: zautomatyzowaną (skryptową) oraz w pełni manualną krok po kroku. Proces weryfikacji i testu (pętla w Javie) jest wspólny dla obu dróg.

---

## Metoda 1: Szybka Ścieżka Automatyczna (Zalecana)

Aby aplikacje mogły bezbłędnie i bezutratnie odtworzyć swoje sesje i w locie "powtórzyć" (replay) przerwane transakcje na węźle Standby, muszą łączyć się przez specjalnie przygotowany serwis aplikacyjny `MYAPP_TAC`. Skonfigurowanie tego serwisu oraz powiadomień ONS można wykonać za pomocą dwóch dostarczonych skryptów.

```bash
# 1. Tworzenie serwisu MYAPP_TAC (jako użytkownik oracle na prim01)
su - oracle
bash /tmp/scripts/setup_tac_services.sh

# 2. Konfiguracja Cross-Site ONS (jako użytkownik grid na prim01)
# Ważne: polecenie modyfikujące ONS klastra powino być wykonywane jako właściciel GI!
su - grid
bash /tmp/scripts/setup_cross_site_ons.sh
```

> **Co skrypty robią pod spodem (zaszyte lekcje):**
> - **`setup_tac_services.sh`** — (a) idempotentny: `srvctl config service` check → `modify` zamiast `add` jeśli istnieje (F-12, lekcja: re-run safe); (b) flagi TAC w tablicy bash (`failovertype TRANSACTION`, `failover_restore LEVEL1`, `commit_outcome TRUE`, `session_state DYNAMIC`, `notification TRUE` itd.); (c) `set -euo pipefail` (fail-fast); (d) post-create verify `failover_type|failover_restore|commit_outcome` przez grep; (e) auto-rejestracja na stby01 przez SSH `setup_tac_services_stby.sh` (Krok 1.5 manualnej).
> - **`setup_cross_site_ons.sh`** — (a) `srvctl modify ons -remoteservers` BEZ flagi `-clusterid` (usunięta w 26ai, VMs/FIX-040); (b) zdalna rekonfiguracja `ons.config` na stby01 z 3 nodami `nodes=...` (VMs/FIX-082 Luka 2); (c) systemd unit `oracle-ons.service` Type=forking (VMs/FIX-083 — persistence po reboocie stby01); (d) `onsctl ping` sanity-check.

Jeżeli uruchomiłeś oba skrypty, przejdź bezpośrednio do sekcji **Weryfikacja Poprawności (Readiness Check)**.

---

## Metoda 2: Ścieżka Manualna (Krok po kroku)

Dla osób chcących zaimplementować parametry samemu przy użyciu narzędzi `srvctl` oraz zmodyfikować konfigurację na węźle Standby bez pomocy skryptów.

### Krok 1: Utworzenie Serwisu Aplikacyjnego TAC na klastrze

> **Pre-flight (przed `srvctl add service`):** sprawdź że (a) baza działa (`srvctl status database -db PRIM` → "Instance PRIM1/PRIM2 is running"), (b) PDB zarejestrowane w listenerze (`lsnrctl services | grep APPPDB`), (c) broker w stanie SUCCESS (`dgmgrl /@PRIM_ADMIN "SHOW CONFIGURATION"`). Lekcja: VMs/FIX-080 — bez tych sprawdzeń DBA debuguje TAC replay 1-2h zanim znajdzie root cause.

> **Idempotency:** jeśli serwis już istnieje (re-run procedury), `srvctl add` zwróci `PRCD-1126: service already exists`. Wtedy zamiast `add` użyj `srvctl modify service -db PRIM -service MYAPP_TAC <flagi>`. Skrypt automatyczny `setup_tac_services.sh` (F-12) wykrywa to automatycznie.

Zaloguj się na **`prim01`** jako użytkownik **`oracle`** i utwórz specjalny serwis wyposażony w mechanizmy TAC (Application Continuity):

```bash
# Jako oracle na prim01
srvctl add service \
    -db PRIM \
    -service MYAPP_TAC \
    -preferred PRIM1,PRIM2 \
    -pdb APPPDB \
    -failovertype TRANSACTION \
    -failover_restore LEVEL1 \
    -commit_outcome TRUE \
    -session_state DYNAMIC \
    -retention 86400 \
    -replay_init_time 1800 \
    -drain_timeout 300 \
    -stopoption IMMEDIATE \
    -role PRIMARY \
    -notification TRUE \
    -rlbgoal SERVICE_TIME \
    -clbgoal SHORT \
    -failoverretry 30 \
    -failoverdelay 10 \
    -policy AUTOMATIC

# Uruchamianie serwisu
srvctl start service -db PRIM -service MYAPP_TAC

# Weryfikacja kluczowych atrybutów TAC
srvctl config service -db PRIM -service MYAPP_TAC | \
  grep -E 'Pluggable|Failover type|Failover restore|Commit Outcome|Retention|Drain|Session State|Notification'
# Oczekiwane: Failover type: TRANSACTION, Failover restore: LEVEL1, Commit Outcome: true, ...
```

### Krok 1.5: Rejestracja serwisu w Oracle Restart na `stby01` (równolegle do RAC)

> **Kluczowe dla post-failover auto-start.** `stby01` ma **Grid Infrastructure for a Standalone Server (Oracle Restart)** — nie jest "gołym" Single Instance. CRS na poziomie hosta zarządza bazą i jej serwisami **analogicznie** jak Grid Cluster na RAC. Jeśli zarejestrujemy `MYAPP_TAC` z `-role PRIMARY` na Oracle Restart stby01, **CRS sam wystartuje serwis po failoverze** (gdy STBY zmieni rolę na PRIMARY) — bez potrzeby ręcznego `DBMS_SERVICE.START_SERVICE`.

```bash
# Jako oracle na stby01
srvctl add service \
    -db STBY \
    -service MYAPP_TAC \
    -pdb APPPDB \
    -failovertype TRANSACTION \
    -failover_restore LEVEL1 \
    -commit_outcome TRUE \
    -session_state DYNAMIC \
    -retention 86400 \
    -replay_init_time 1800 \
    -drain_timeout 300 \
    -stopoption IMMEDIATE \
    -role PRIMARY \
    -notification TRUE \
    -rlbgoal SERVICE_TIME \
    -clbgoal SHORT \
    -failoverretry 30 \
    -failoverdelay 10 \
    -policy AUTOMATIC

# UWAGA: serwis NIE startuje teraz (stby01 ma rolę PHYSICAL_STANDBY) — atrybut
# -role PRIMARY mówi Oracle Restart "uruchom mnie tylko gdy ta baza jest PRIMARY".
# Po promote (failover/switchover STBY→PRIMARY) Oracle Restart wykryje zmianę
# i automatycznie wystartuje serwis w 5–15 s.
srvctl status service -db STBY -service MYAPP_TAC
# Service MYAPP_TAC is not running.   ← oczekiwane przed failover.
```

> **Idempotency:** jak w Kroku 1, jeśli serwis już istnieje (re-run) → `PRCD-1126`. Użyj `srvctl modify service -db STBY -service MYAPP_TAC <flagi>` zamiast `add`.

> 💡 W ścieżce automatycznej `setup_tac_services.sh` wywołuje `setup_tac_services_stby.sh` przez SSH — krok 1.5 dzieje się automatycznie.

### Krok 2: Skonfigurowanie powiadomień FAN (ONS) na klastrze

Po awarii klastra głównego, klienci muszą w ułamku sekundy dowiedzieć się, że Primary uległo awarii i przesterować sygnał na `stby01`.

> **Uwaga (VMs/FIX-040 / 26ai):** flaga `-clusterid` została **usunięta** w 26ai. W 19c poprawne było `srvctl modify ons -clusterid <ONS_id> -remoteservers ...`. W 26ai przekazujemy **wyłącznie** `-remoteservers`.

> **Pre-req firewall (VMs/FIX-011):** port **6200/tcp** musi być dostępny pomiędzy prim01/02 ↔ stby01. W naszym labie firewall jest wyłączony (kickstart), w produkcji koniecznie otwórz: `firewall-cmd --permanent --add-port=6200/tcp && firewall-cmd --reload`. Bez tego klient UCP nie odbierze FAN events → brak replay TAC.

```bash
# Jako grid na prim01 — re-run safe (modify zastępuje konfigurację)
srvctl modify ons -remoteservers stby01.lab.local:6200

# Weryfikacja
srvctl config ons | grep -E 'Cluster|Remote'
```

### Krok 3: Skonfigurowanie ONS na węźle Standby (`stby01`) — Oracle Restart

> **F-13:** `stby01` to Single Instance + Oracle Restart (NIE GI Cluster), więc `ons` **nie jest CRS-resource** i nie da się go zarządzać przez `srvctl modify ons` jak na klastrze RAC. Konfiguracja jest plikowa + ręczny `onsctl`.

```bash
# Jako oracle na stby01
mkdir -p /u01/app/oracle/product/23.26/dbhome_1/opmn/conf

cat > /u01/app/oracle/product/23.26/dbhome_1/opmn/conf/ons.config <<EOF
usesharedinstall=true
localport=6100
remoteport=6200
nodes=stby01.lab.local:6200,prim01.lab.local:6200,prim02.lab.local:6200
EOF
# S28-62: w 26ai klucze 'loglevel' i 'useocr' są UNKNOWN (warning w onsctl ping).
# Jeśli widzisz "unkown key: loglevel" w logu - usuń te linie z ons.config.

export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH

onsctl stop 2>/dev/null || true
onsctl start
onsctl ping        # Oczekiwane: "Number of ons configured = 3" + "ons is running"
```

#### Krok 3.a — Persystencja przez systemd (po reboocie stby01)

> **Pułapka (S28-62):** ExecStart bezpośrednio do `onsctl start` daje `status=203/EXEC` — onsctl wymaga pełnego env (`LD_LIBRARY_PATH`, `PATH`), nie tylko `ORACLE_HOME` jak w `Environment=` dyrektywie systemd. Identyczny problem jak S28-54 dla observera. Rozwiązanie: wrapper script.

Aby `ons` startował automatycznie po restarcie `stby01`:

**Krok 3.a.1 — Wrapper scripts (jako root):**
```bash
cat > /usr/local/bin/start-ons.sh <<'EOF'
#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:/usr/lib
exec $ORACLE_HOME/bin/onsctl start
EOF

cat > /usr/local/bin/stop-ons.sh <<'EOF'
#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:/usr/lib
exec $ORACLE_HOME/bin/onsctl stop
EOF

chmod 755 /usr/local/bin/start-ons.sh /usr/local/bin/stop-ons.sh
```

**Krok 3.a.2 — Unit systemd:**
```bash
# Jako root
cat > /etc/systemd/system/oracle-ons.service <<'EOF'
[Unit]
Description=Oracle ONS daemon (FAN events for Standby)
After=network-online.target

[Service]
Type=forking
User=oracle
Group=oinstall
ExecStart=/usr/local/bin/start-ons.sh
ExecStop=/usr/local/bin/stop-ons.sh
Restart=on-failure
RestartSec=15

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now oracle-ons.service

# Weryfikacja
systemctl status oracle-ons.service --no-pager -l | head -10
su - oracle -c 'export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1; export LD_LIBRARY_PATH=$ORACLE_HOME/lib; $ORACLE_HOME/bin/onsctl ping'
# Oczekiwane: "ons is running ..."
```

> Po failoverze klient UCP odbiera FAN-event "service moved to standby" w czasie < 1 s zamiast czekać na timeout TCP.

---

## 3.0 Pre-flight: użytkownik aplikacyjny i tabela `test_log` (F-10)

Aplikacja `TestHarness.java` wykonuje `INSERT INTO app_user.test_log (instance, session_id, message)` — **tabela musi istnieć w PDB `APPPDB`** zanim klient ruszy. Jednorazowe DDL:

```bash
# Jako oracle na prim01
sqlplus -s / as sysdba <<'EOF'
ALTER SESSION SET CONTAINER=APPPDB;

-- Konwencja labu: wszystkie hasla = Oracle26ai_LAB! (zob. 01_Architektura sekcja 2).
CREATE USER app_user IDENTIFIED BY "Oracle26ai_LAB!";
GRANT CREATE SESSION, CREATE TABLE, UNLIMITED TABLESPACE TO app_user;
-- KEEP grants są wymagane dla pełnego TAC replay (transaction guard).
GRANT KEEP DATE TIME, KEEP SYSGUID TO app_user;

ALTER SESSION SET CURRENT_SCHEMA=app_user;
CREATE TABLE app_user.test_log (
    id          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    instance    VARCHAR2(16),
    session_id  NUMBER,
    message     VARCHAR2(1000),
    created     TIMESTAMP DEFAULT SYSTIMESTAMP
);
GRANT INSERT, SELECT ON app_user.test_log TO app_user;
EOF
```

> **Bezpieczeństwo:** w **labie** zachowujemy konwencję pojedynczego hasła `Oracle26ai_LAB!` dla wszystkich kont (uproszczenie diagnostyczne — nigdy w produkcji). W **produkcji** zastąp powyższe hasło wartością z secret store i ustaw `APP_PASSWORD` (lub `LAB_PASS`) jako zmienną środowiskową przed uruchomieniem `TestHarness`. Sam klient ma trzystopniowy fallback: `APP_PASSWORD` env → `LAB_PASS` env → wbudowany lab-default `Oracle26ai_LAB!`.

---

## 3. Weryfikacja Poprawności (Readiness Check)

Przed wpuszczeniem aplikacji klienckich, upewnijmy się, że baza danych jest gotowa na TAC.

### 3.1 Pre-flight network/daemon (VMs/FIX-080 F5/F7)

```bash
# Z prim01 jako oracle: dostępność ONS na stby01
nc -zv -w 5 stby01.lab.local 6200
# Oczekiwane: "Connection to stby01.lab.local 6200 port [tcp/*] succeeded!"

# Sprawdzenie demona ONS na stby01
ssh oracle@stby01 'onsctl ping'
# Oczekiwane: "Number of ons configured = 3" + "ons is running"
```

### 3.2 Pełny readiness check (TAC + broker + FSFO + Flashback)

Z repozytorium projektu wgramy do maszyny wszystkie zawarte tam skrypty z katalogu `/tmp/sql/`.
(Gdzie `<repo>` oznacza główny folder naszego nowego projektu `VMs2-install`).

> **Uwaga (VMs/FIX-082 Luka 1):** używamy wariantu `_26ai` skryptu, ponieważ w 23ai/26ai widok `GV$REPLAY_STAT_SUMMARY` został usunięty — oryginalny `tac_full_readiness.sql` (19c) by sypnął ORA-00942.

```bash
# Jako oracle na prim01, uruchom skrypt walidacyjny:
sqlplus -s / as sysdba @/tmp/sql/tac_full_readiness_26ai.sql
```
Jeżeli widzisz w kolumnach powiadomienia **PASS**, system jest w 100% gotowy na usterki środowiskowe.

---

## 4. Przygotowanie Środowiska Klienckiego (`client01`)

Zanim uruchomimy aplikację testową w Javie, musimy przygotować maszynę kliencką. W środowisku produkcyjnym byłyby to maszyny aplikacyjne (Application Servers).

Zaloguj się na **`client01`** jako użytkownik **`root`**.

### Krok 4.1. Instalacja środowiska uruchomieniowego (Java 17)

```bash
# Instalacja OpenJDK 17
dnf install -y java-17-openjdk java-17-openjdk-devel

# Ustawienie nowej Javy jako domyślnej
JAVA17=$(ls -d /usr/lib/jvm/java-17-openjdk-*/bin/java | head -1)
alternatives --set java "$JAVA17"

# Stworzenie struktury katalogów na aplikację i biblioteki
mkdir -p /opt/lab/jars
mkdir -p /opt/lab/src
mkdir -p /opt/lab/tns
chown -R oracle:oinstall /opt/lab
```

### Krok 4.2. Instalacja bibliotek JDBC i UCP

Przeloguj się na **`client01`** jako użytkownik **`oracle`**. Skopiuj sterowniki bazy z dowolnej innej maszyny klastra (np. `prim01`):

```bash
# Kopiowanie wymaganych bilbiotek z maszyny głównej
scp oracle@prim01:/u01/app/oracle/product/23.26/dbhome_1/jdbc/lib/ojdbc11.jar /opt/lab/jars/
scp oracle@prim01:/u01/app/oracle/product/23.26/dbhome_1/ucp/lib/ucp11.jar /opt/lab/jars/
scp oracle@prim01:/u01/app/oracle/product/23.26/dbhome_1/opmn/lib/ons.jar /opt/lab/jars/
scp oracle@prim01:/u01/app/oracle/product/23.26/dbhome_1/jlib/oraclepki.jar /opt/lab/jars/
scp oracle@prim01:/u01/app/oracle/product/23.26/dbhome_1/jdbc/lib/simplefan.jar /opt/lab/jars/
```

### Krok 4.3. Konfiguracja połączenia sieciowego

```bash
cat > /opt/lab/tns/tnsnames.ora <<'EOF'
MYAPP_TAC =
  (DESCRIPTION =
    (CONNECT_TIMEOUT=10)(RETRY_COUNT=20)(RETRY_DELAY=3)
    (TRANSPORT_CONNECT_TIMEOUT=3)
    (ADDRESS_LIST =
      (LOAD_BALANCE = OFF)
      (FAILOVER = ON)
      (ADDRESS = (PROTOCOL = TCP)(HOST = scan-prim.lab.local)(PORT = 1521))
      (ADDRESS = (PROTOCOL = TCP)(HOST = stby01.lab.local)(PORT = 1521))
    )
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = MYAPP_TAC.lab.local)
    )
  )
EOF

# Eksport zmiennej środowiskowej
export TNS_ADMIN=/opt/lab/tns
echo "export TNS_ADMIN=/opt/lab/tns" >> ~/.bash_profile
```

---

## 5. Test aplikacji w Javie (UCP + TAC)

Projekt w katalogu `/tmp/src/` zawiera testową aplikację w Javie: `TestHarness.java`.

> **KRYTYCZNE (VMs/FIX-084 F1):** UCP klient MUSI używać `oracle.jdbc.replay.OracleDataSourceImpl` jako `setConnectionFactoryClassName(...)`. Standardowy `oracle.jdbc.pool.OracleDataSource` **NIE wspiera replay** — po failoverze klient dostanie `ORA-03113: end-of-file on communication channel` zamiast transparentnego replay. Sprawdź w `TestHarness.java`:
> ```java
> pds.setConnectionFactoryClassName("oracle.jdbc.replay.OracleDataSourceImpl");  // ← TAC
> pds.setValidateConnectionOnBorrow(true);                                       // ← UCP best practice (FIX-084 V_C_O_B)
> ```

### Krok 5.1. Kompilacja i uruchomienie

Będąc na **`client01`** jako użytkownik **`oracle`**, wgraj plik Java:
```bash
# Zakładając że zgrałeś plik z /tmp/src/TestHarness.java do /opt/lab/src/
cp /tmp/src/TestHarness.java /opt/lab/src/
cd /opt/lab/src

# Kompilacja
javac -cp '/opt/lab/jars/*' TestHarness.java

# Uruchomienie (wymagane obejścia modułów dla Java 17+ by wygenerować proxy dla klas TAC w 23.x)
# UWAGA (S28-63): -Doracle.net.tns_admin=... JEST WYMAGANE — JDBC thin nie czyta env TNS_ADMIN.
# Bez tego: `ORA-17868: Unknown host specified.: MYAPP_TAC: Name or service not known`.
java -Doracle.net.tns_admin=/opt/lab/tns \
     --add-opens=java.base/java.lang=ALL-UNNAMED \
     --add-opens=java.base/java.util=ALL-UNNAMED \
     --add-opens=java.base/jdk.internal.misc=ALL-UNNAMED \
     --add-opens=java.base/sun.nio.ch=ALL-UNNAMED \
     -cp '/opt/lab/jars/*:.' TestHarness
```

Powinieneś zobaczyć wynik komunikacji Load Balancera (skakanie między `PRIM1` i `PRIM2`):
```text
[1] SUKCES: PRIM1  SID=502  rows=1
[2] SUKCES: PRIM2  SID=212  rows=1
...
```

Dalsze warianty testowania tego kodu (m.in wywoływanie rzeczywistych awarii, brutalne ubijanie procesów instancji w locie i blokady mechanizmu Data Guard) są szczegółowo rozpisane w **Kroku 09**.

---
**Następny krok:** `09_Test_Scenarios_PL.md`

