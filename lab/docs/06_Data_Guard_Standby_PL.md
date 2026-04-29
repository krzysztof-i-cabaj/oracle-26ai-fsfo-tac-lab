> [🇬🇧 English](./06_Data_Guard_Standby.md) | 🇵🇱 Polski

# 06 — Tworzenie Standby via Data Guard Broker (VMs2-install)

> **Cel:** Instalacja fizycznej bazy zapasowej (Physical Standby `STBY`) na węźle `stby01` z użyciem najnowszego, uproszczonego podejścia opartego na narzędziu **Data Guard Broker (DGMGRL)**. Metoda ta eliminuje konieczność ręcznego pisania długich skryptów RMAN DUPLICATE, a całą złożoność (kopiowanie plików, aplikowanie parametrów w tle) bierze na siebie sam broker.

Dokument opisuje dwie metody wdrożenia: zautomatyzowaną (skryptową) oraz w pełni manualną krok po kroku.

---

## 0. Wymaganie wstępne: Instalacja oprogramowania DB na stby01

> **Zależność:** Skrypt `create_standby_broker.sh` kopiuje plik haseł na `stby01` do katalogu `$ORACLE_HOME/dbs/`. Katalog ten istnieje dopiero po instalacji oprogramowania bazy. Bez tego kroku skrypt zakończy się błędem `scp: /u01/app/oracle/.../dbs/: No such file or directory`.

### Metoda automatyczna (Zalecana)

Zaloguj się na **`stby01`** jako użytkownik **`oracle`**:

```bash
bash /tmp/scripts/install_db_silent.sh /tmp/response_files/db_stby.rsp
```

> **Uwaga:** Używamy `db_stby.rsp`, **nie** `db.rsp`. Różnica: `db_stby.rsp` ma pusty parametr `CLUSTER_NODES` (stby01 to Standalone Server / Oracle Restart, nie klaster RAC). Z wypełnionym `CLUSTER_NODES=prim01,prim02` installer próbuje rejestrować home w CRS RAC i kończy błędem.

Po zakończeniu instalatora — jako **`root`** na **`stby01`**:

```bash
/u01/app/oracle/product/23.26/dbhome_1/root.sh
```

### Metoda manualna

```bash
# Jako oracle na stby01
export DB_HOME="/u01/app/oracle/product/23.26/dbhome_1"
export DB_ZIP="/mnt/oracle_binaries/V1054592-01-OracleDatabase23.26.1.0.0forLinux_x86-64.zip"
export CV_ASSUME_DISTID=OEL8.10

cd $DB_HOME
unzip -q $DB_ZIP

$DB_HOME/runInstaller -silent -ignorePrereqFailure \
    -responseFile /tmp/response_files/db_stby.rsp
```

```bash
# Jako root na stby01 — po zakończeniu runInstaller
/u01/app/oracle/product/23.26/dbhome_1/root.sh
```

### Weryfikacja

```bash
# Jako oracle na stby01
ls /u01/app/oracle/product/23.26/dbhome_1/dbs/
# Katalog dbs/ musi istnieć — to sygnał gotowości do kolejnych kroków.

cat /u01/app/oraInventory/ContentsXML/inventory.xml | grep -i "oracle.server"
# Oczekiwane: HOME NAME="OraDB23Home1" LOC="/u01/app/oracle/product/23.26/dbhome_1"
```

Gdy `dbs/` istnieje i inventory potwierdza rejestrację — przejdź do sekcji poniżej.

---

## 1. Architektura Sieci i Wymagania

Aby Data Guard Broker mógł samodzielnie "zbudować" bazę na zdalnym węźle `stby01`, muszą być spełnione trzy warunki:
1. Posiadamy plik haseł (tzw. `orapwPRIM` skopiowany jako `orapwSTBY`) na zdalnej maszynie, aby połączenia `AS SYSDBA` przez sieć były uwierzytelniane.
2. Zbudowana jest pełna siatka kluczy (Full Mesh) SSH – to zostało już zrobione w kroku *02_OS_and_Network_Preparation*.
3. Na serwerze docelowym (`stby01`) instancja jest uruchomiona w stanie "pustym", czyli `NOMOUNT` z użyciem prostego pliku inicjalizacyjnego (`initSTBY.ora`).
4. Uruchomiony jest na obu stronach lokalny `LISTENER` oraz odpowiednie wpisy `tnsnames.ora`.

Wszystkie te pre-konfiguracje, jak i samo wywołanie DGMGRL, można zautomatyzować lub wykonać ręcznie.

---

## Metoda 1: Szybka Ścieżka Automatyczna (Zalecana)

Ten proces realizujesz w 100% z poziomu węzła głównego **`prim01`**. Skrypt samodzielnie wstrzykuje pliki na węzeł `stby01`.

### Krok 0: Plik z hasłem LAB_PASS (prim01, oracle)

Skrypt `create_standby_broker.sh` wymaga zmiennej `LAB_PASS` (hasło SYS do wallet DGMGRL). Utwórz plik `~/.lab_secrets` na **`prim01`** jako **`oracle`**:

```bash
cat > ~/.lab_secrets << 'EOF'
export LAB_PASS='Oracle26ai_LAB!'
EOF
chmod 600 ~/.lab_secrets
cat ~/.lab_secrets
# Oczekiwane: export LAB_PASS='Oracle26ai_LAB!'
```

> **Uwaga:** Nie używaj `echo "export LAB_PASS='Oracle26ai_LAB!'"` — bash interpretuje `!` w podwójnych cudzysłowach jako rozwinięcie historii i zwraca błąd `event not found`. Zawsze używaj heredoc `<< 'EOF'` (apostrof przy EOF wyłącza rozwinięcia).

### Krok 1: Uruchomienie skryptu

```bash
# Jako oracle na prim01
# Skrypt potrwa kilka-kilkanaście minut (zależnie od wydajności I/O)
# RMAN DUPLICATE będzie uruchomiony w tle przez proces Brokera.
nohup bash /tmp/scripts/create_standby_broker.sh > /tmp/create_standby.log 2>&1 &

# Podglądaj proces:
tail -f /tmp/create_standby.log
```

Jeśli użyłeś tej ścieżki, możesz od razu przejść do sekcji **Weryfikacja**.

---

## Metoda 2: Ścieżka Manualna (Krok po kroku)

Dla osób, które chcą prześledzić komendy lub zdebugować ewentualne problemy, przygotowaliśmy kompletną listę kroków.

### Krok 1: Kopiowanie pliku haseł na serwer Standby

Operację wykonujemy na węźle głównym **`prim01`** jako użytkownik `oracle`:

> **Uwaga GI/RAC — `/etc/oratab` i `oraenv`:** W środowisku Oracle Grid Infrastructure (11gR2+)
> RAC instance (PRIM1, PRIM2) **nie mają wpisów w `/etc/oratab`** — CRS/OCR jest source of truth.
> `oraenv` wywołuje `dbhome PRIM1`, które zwraca `/home/oracle` gdy brak wpisu → exit 2 → błąd skryptu.
> W skryptach RAC używaj `ORACLE_HOME` wprost lub przez `srvctl config database -db PRIM`.
> (Oracle GI Admin Guide: *"For Oracle RAC databases, do not use the oratab file to manage database startup"*)

```bash
# FIX-S28-27/28: orapwd odrzuca "oracle" w haśle (OPW-00029); asmcmd pwcopy wymaga
# ORACLE_SID=+ASM1 i chmod 1777 na katalogu docelowym (grid pisze przez proces ASM).
mkdir -p /tmp/pwd
chmod 1777 /tmp/pwd   # grid (proces ASM) musi mieć prawo zapisu
export ORACLE_SID=+ASM1
PWFILE=$(asmcmd pwget --dbuniquename PRIM)
asmcmd pwcopy "$PWFILE" /tmp/pwd/orapwPRIM -f
export ORACLE_SID=PRIM1

# Skopiuj plik przez SSH na zdalną maszynę stby01
scp /tmp/pwd/orapwPRIM oracle@stby01:/u01/app/oracle/product/23.26/dbhome_1/dbs/orapwSTBY
```

### Krok 2: Konfiguracja infrastruktury na węźle Standby (`stby01`)

Przeloguj się na **`stby01`** jako użytkownik `oracle`. Przygotuj pliki sieciowe, utwórz wymagane foldery danych i uruchom pustą instancję.

```bash
# Jako oracle na stby01
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export ORACLE_SID=STBY
export PATH=$ORACLE_HOME/bin:$PATH

# Tworzenie fizycznych katalogów na bazie XFS (zgodnie z architekturą labu)
mkdir -p $ORACLE_HOME/network/admin
mkdir -p /u01/app/oracle/admin/STBY/adump
mkdir -p /u02/oradata/STBY/onlinelog
mkdir -p /u03/fra/STBY/onlinelog

# FIX-S28-50: LISTENER (1521) na stby01 jako HAS resource — auto-start po reboot.
# Domyślnie CRS_SWONLY install + roothas.pl NIE tworzy ora.LISTENER.lsnr — bez tego po reboot
# stby01 listener nie wstaje → ORA-16778 (broker redo transport error). listener.ora w GRID_HOME.
# FIX-040 / S28-29: GLOBAL_DBNAME z suffixem .lab.local (db_domain=lab.local).
# Wykonaj jako grid (root@stby01 → su - grid):
mkdir -p /u01/app/23.26/grid/network/admin
cat >> /u01/app/23.26/grid/network/admin/listener.ora <<'LORA'

LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = stby01.lab.local)(PORT = 1521))
    )
  )

SID_LIST_LISTENER =
  (SID_LIST =
    (SID_DESC =
      (GLOBAL_DBNAME = STBY.lab.local)
      (ORACLE_HOME = /u01/app/oracle/product/23.26/dbhome_1)
      (SID_NAME = STBY)
    )
    (SID_DESC =
      (GLOBAL_DBNAME = STBY_DGMGRL.lab.local)
      (ORACLE_HOME = /u01/app/oracle/product/23.26/dbhome_1)
      (SID_NAME = STBY)
    )
  )
LORA

srvctl add listener -listener LISTENER -endpoints 'TCP:1521'
srvctl start listener -listener LISTENER
srvctl status listener -listener LISTENER
# Oczekiwane: Listener LISTENER is enabled, running on node(s): stby01

# Verify
lsnrctl status LISTENER | grep -E 'STATUS|Service'
# Oczekiwane: STATUS Ready, Parameter File z GRID_HOME path

# TNSNAMES dla stby01
# FIX-040: SERVICE_NAME musi miec suffix .lab.local (Oracle 23.26.1 z db_domain=lab.local)
# FIX-S28-31: ADDRESS_LIST z node IPs zamiast SCAN — SCAN listener nie widzi PRIM.lab.local
# gdy remote_listener nie jest ustawiony. Lokalne listenery na prim01/prim02 maja serwis.
# FIX-S28-38: LOAD_BALANCE=off + FAILOVER=on — RMAN Active Duplicate wymaga deterministycznego
# connecta do JEDNEJ instancji RAC. Bez tego AUX RPC back do TARGET trafia na rozne nody →
# ORA-01138 podczas DBMS_BACKUP_RESTORE.RESTORESETPIECE.
cat > $ORACLE_HOME/network/admin/tnsnames.ora <<TORA
PRIM =
  (DESCRIPTION =
    (ADDRESS_LIST =
      (LOAD_BALANCE = off)
      (FAILOVER = on)
      (ADDRESS = (PROTOCOL = TCP)(HOST = prim01.lab.local)(PORT = 1521))
      (ADDRESS = (PROTOCOL = TCP)(HOST = prim02.lab.local)(PORT = 1521))
    )
    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = PRIM.lab.local))
  )
STBY =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = stby01.lab.local)(PORT = 1521))
    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = STBY.lab.local))
  )
TORA

# LISTENER 1521 wystartowany juz przez `srvctl start listener` (HAS) powyzej — NIE startuj recznie.
# LISTENER_DGMGRL (1522) bedzie skonfigurowany jako CRS/HAS resource dalej (krok 4a/4b).

# FIX-S28-30: Oracle Restart automatycznie uruchamia STBY po instalacji DB — zatrzymaj przed NOMOUNT
srvctl stop database -db STBY 2>/dev/null || true

# FIX-S28-37: cleanup pozostałości po nieudanych próbach (datafiles, controlfile, SPFILE).
# Bez tego RMAN DUPLICATE może rzucać ORA-19660/ORA-19685 verification failures.
rm -f /u02/oradata/STBY/*.dbf /u02/oradata/STBY/*.ctl 2>/dev/null || true
rm -rf /u02/oradata/STBY/onlinelog/* 2>/dev/null || true
rm -f /u03/fra/STBY/*.ctl 2>/dev/null || true
rm -rf /u03/fra/STBY/onlinelog/* 2>/dev/null || true
rm -rf /u03/fra/STBY/STBY 2>/dev/null || true
rm -f $ORACLE_HOME/dbs/spfileSTBY.ora 2>/dev/null || true
# FIX-S28-42: usuń stare pliki konfig brokera ze STBY — pozostałe po nieudanych ENABLE
# powodują ORA-16603 "member is part of another DG config" przy ADD DATABASE STBY z PRIM.
rm -f $ORACLE_HOME/dbs/dr1STBY.dat $ORACLE_HOME/dbs/dr2STBY.dat 2>/dev/null || true

# Utworzenie minimalnego pliku PFILE (initSTBY.ora) i STARTUP NOMOUNT
cat > $ORACLE_HOME/dbs/initSTBY.ora <<IORA
db_name=PRIM
db_unique_name=STBY
sga_target=2048M
IORA

sqlplus -s / as sysdba <<SQL
SHUTDOWN ABORT;
STARTUP NOMOUNT PFILE='$ORACLE_HOME/dbs/initSTBY.ora';
ALTER SYSTEM SET DG_BROKER_START=TRUE;
EXIT;
SQL
```

### Krok 3: Konfiguracja Primary i Brokera (`prim01`)

Zaloguj się z powrotem na **`prim01`** jako `oracle`. Przygotuj plik TNSNAMES, wymuś działanie procesu brokera na obu węzłach RAC i wywołaj komendę duplikującą bazę.

```bash
# Jako oracle na prim01
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export ORACLE_SID=PRIM1

# Aktualizacja TNSNAMES na klastrze
# FIX-040: SERVICE_NAME musi miec suffix .lab.local (Oracle 23.26.1 z db_domain=lab.local)
# FIX-S28-31: ADDRESS_LIST z node IPs zamiast SCAN — SCAN listener nie widzi PRIM.lab.local
# gdy remote_listener nie jest ustawiony. Lokalne listenery na prim01/prim02 maja serwis.
# FIX-S28-38: LOAD_BALANCE=off + FAILOVER=on — RMAN Active Duplicate wymaga deterministycznego
# connecta do JEDNEJ instancji RAC. Bez tego AUX RPC back do TARGET trafia na rozne nody →
# ORA-01138 podczas DBMS_BACKUP_RESTORE.RESTORESETPIECE.
cat > $ORACLE_HOME/network/admin/tnsnames.ora << 'EOF'
PRIM =
  (DESCRIPTION =
    (ADDRESS_LIST =
      (LOAD_BALANCE = off)
      (FAILOVER = on)
      (ADDRESS = (PROTOCOL = TCP)(HOST = prim01.lab.local)(PORT = 1521))
      (ADDRESS = (PROTOCOL = TCP)(HOST = prim02.lab.local)(PORT = 1521))
    )
    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = PRIM.lab.local))
  )
STBY =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = stby01.lab.local)(PORT = 1521))
    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = STBY.lab.local))
  )
EOF
scp $ORACLE_HOME/network/admin/tnsnames.ora prim02:$ORACLE_HOME/network/admin/tnsnames.ora

# FIX-S28-49 (CRS-managed): LISTENER_DGMGRL na port 1522 jako CRS/HAS resource — auto-start
# po reboot bez ręcznych komend. Listener.ora idzie do GRID_HOME (grid user), srvctl add
# listener rejestruje resource w CRS (RAC: prim01+prim02) lub HAS (stby01).
# Bez tego listener observerowie z infra01 nie podłączą przez alias PRIM_ADMIN (port 1522).

# === RAC nodes (prim01/prim02) — append do GRID_HOME listener.ora ===
for NODE in prim01 prim02; do
    case "$NODE" in
        prim01) NODE_SID=PRIM1 ;;
        prim02) NODE_SID=PRIM2 ;;
    esac
    ssh grid@${NODE} "cat >> /u01/app/23.26/grid/network/admin/listener.ora" <<LSNREOF

LISTENER_DGMGRL =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = ${NODE}.lab.local)(PORT = 1522))
  )

SID_LIST_LISTENER_DGMGRL =
  (SID_LIST =
    (SID_DESC =
      (GLOBAL_DBNAME = PRIM_DGMGRL.lab.local)
      (ORACLE_HOME = /u01/app/oracle/product/23.26/dbhome_1)
      (SID_NAME = ${NODE_SID})
    )
  )
LSNREOF
done

# srvctl add cluster-wide (jeden CRS resource ora.LISTENER_DGMGRL.lsnr na obu nodach)
ssh grid@prim01 "srvctl add listener -listener LISTENER_DGMGRL -endpoints 'TCP:1522'"
ssh grid@prim01 "srvctl start listener -listener LISTENER_DGMGRL"
ssh grid@prim01 "srvctl status listener -listener LISTENER_DGMGRL"
# Oczekiwane: Listener LISTENER_DGMGRL is enabled, running on node(s): prim01,prim02

# === stby01 (Oracle Restart, HAS) — listener.ora w GRID_HOME, HAS resource ===
ssh grid@stby01 "mkdir -p /u01/app/23.26/grid/network/admin && cat >> /u01/app/23.26/grid/network/admin/listener.ora" <<'LSNREOF'

LISTENER_DGMGRL =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = stby01.lab.local)(PORT = 1522))
  )

SID_LIST_LISTENER_DGMGRL =
  (SID_LIST =
    (SID_DESC =
      (GLOBAL_DBNAME = STBY_DGMGRL.lab.local)
      (ORACLE_HOME = /u01/app/oracle/product/23.26/dbhome_1)
      (SID_NAME = STBY)
    )
  )
LSNREOF

ssh grid@stby01 "srvctl add listener -listener LISTENER_DGMGRL -endpoints 'TCP:1522'"
ssh grid@stby01 "srvctl start listener -listener LISTENER_DGMGRL"
ssh grid@stby01 "srvctl status listener -listener LISTENER_DGMGRL"

# Verify CRS/HAS resource — STATE=ONLINE
ssh root@prim01 "/u01/app/23.26/grid/bin/crsctl stat res -t | grep -B1 -A2 -i listener_dgmgrl"
ssh root@stby01 "/u01/app/23.26/grid/bin/crsctl stat res -t | grep -B1 -A2 -i listener_dgmgrl"

# === FIX-S28-48 trwale: CSSD AUTO_START=always na stby01 ===
# Bez tego po reboot stby01 CSSD jest OFFLINE → srvctl rzuca PRCR-1055.
ssh root@stby01 "/u01/app/23.26/grid/bin/crsctl modify resource ora.cssd -attr 'AUTO_START=always' -init"
ssh root@stby01 "/u01/app/23.26/grid/bin/crsctl status resource ora.cssd -p -init | grep AUTO_START"

# Włączenie DG Brokera dla PRIM1 i PRIM2
# FIX-S28-40: dg_broker_config_file1/2 MUSZĄ być w shared storage (ASM) dla RAC,
# inaczej PRIM2 nie widzi konfig brokera zapisanej przez PRIM1 → ORA-16532 w SHOW CONFIGURATION.
# Ustawiamy PRZED pierwszym DG_BROKER_START=TRUE — broker startując utworzy pliki w ASM.
sqlplus / as sysdba
```
```sql
ALTER SYSTEM SET dg_broker_config_file1='+DATA/PRIM/dr1PRIM.dat' SCOPE=BOTH SID='*';
ALTER SYSTEM SET dg_broker_config_file2='+RECO/PRIM/dr2PRIM.dat' SCOPE=BOTH SID='*';
ALTER SYSTEM SET DG_BROKER_START=TRUE SCOPE=BOTH SID='*';

-- FIX-S28-43: Standby Redo Logs (SRL) na PRIM — wymagane gdy PRIM stanie się standby
-- po switchover. 6 SRL = 3 per thread × 2 thready RAC, każdy o rozmiarze ORL (200M default).
-- W ASM (+DATA) bo PRIM ma OMF skonfigurowane.
ALTER DATABASE ADD STANDBY LOGFILE THREAD 1 GROUP 11 '+DATA' SIZE 200M;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 1 GROUP 12 '+DATA' SIZE 200M;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 1 GROUP 13 '+DATA' SIZE 200M;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 2 GROUP 21 '+DATA' SIZE 200M;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 2 GROUP 22 '+DATA' SIZE 200M;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 2 GROUP 23 '+DATA' SIZE 200M;
EXIT;
```

Budowanie Standby w Oracle 26ai: RMAN Duplicate → Post-RMAN setup → DGMGRL.

> **FIX-061 / FIX-075 / FIX-S28-35:** W Oracle 26ai zmieniono składnię DGMGRL i przepływ tworzenia Physical Standby:
> - `ADD DATABASE ... MAINTAINED AS PHYSICAL` → usunięte (Physical to default, opcja zbędna)
> - `CREATE PHYSICAL STANDBY DATABASE` → **nie istnieje** w 26ai (potwierdzone: `help create` zwraca tylko `CREATE CONFIGURATION` i `CREATE FAR_SYNC`)
> - `CREATE CONFIGURATION` **musi być wywołane PO RMAN Duplicate** — broker startuje asynchronicznie (~20-30s po `DG_BROKER_START=TRUE`). Wywołanie przed RMAN → ORA-16525.
>
> Poprawny przepływ: oczekiwanie na broker → RMAN DUPLICATE → POST-RMAN ALTER SYSTEM → DGMGRL CREATE CONFIG + ADD + ENABLE.

**Krok 6 — Oczekiwanie na gotowość DG Broker (~30s)**

```bash
# Broker startuje asynchronicznie po DG_BROKER_START=TRUE ustawionym na prim01 w kroku 3
sleep 30
```

**Krok 6a — RMAN Active Duplicate (kilkanaście minut)**

> **FIX-043:** RMAN Auxiliary łączy się do STBY przez `SID=STBY` (nie `SERVICE_NAME`), bo w NOMOUNT mode `db_domain` nie jest aktywna — `SERVICE_NAME=STBY.lab.local` nie matchuje listenera.  
> **FIX-042:** Parametr `remote_listener` resetowany (`SET remote_listener = ''`) — RAC primary ma `scan-prim.lab.local`, ale SI standby nie ma SCAN.  
> **FIX-041:** `SET cluster_database = 'FALSE'` — RMAN DUPLICATE kopiuje SPFILE z RAC primary który ma `cluster_database=TRUE`. Na SI standby (stby01) Oracle RAC nie jest dostępne → `ORA-00439: feature not enabled: Real Application Clusters` przy starcie. Wymagany SET w SPFILE klauzuli.  
> **FIX-041 post-RMAN:** `cluster_database_instances` i `instance_number` — NIE mogą być w RMAN SET clause (RMAN-06581 w 26ai). Ustawiamy przez ALTER SYSTEM po starcie standby.  
> **FIX-S28-36:** `SET use_large_pages = 'FALSE'` — RAC primary może mieć `use_large_pages=ONLY` lub `TRUE` (skonfigurowane HugePages na nodach RAC). stby01 nie ma HugePages skonfigurowanych → po restarcie z nowym SPFILE: `ORA-27106: system pages not available to allocate memory`.  
> **FIX-S28-37:** `SET db_create_file_dest`, `db_recovery_file_dest`, `db_recovery_file_dest_size`, `control_files` — RAC primary używa OMF z `db_create_file_dest='+DATA'` i `db_recovery_file_dest='+RECO'`. Klon dziedziczy te ustawienia → na stby01 (XFS, brak ASM) verify backupset fail: `ORA-19660: some files in the backup set could not be verified`, `ORA-19685: SPFILE could not be verified`, `ORA-19845: error in backupSetDatafile`, `ORA-01138: database must either be open in this instance or not at all`. Nadpisz wszystkie OMF-related parametry.  
> **FIX-S28-37 cleanup:** Krok 3 (NOMOUNT) musi czyścić `/u02/oradata/STBY/`, `/u03/fra/STBY/` i `$ORACLE_HOME/dbs/spfileSTBY.ora` z poprzednich nieudanych prób (RMAN nie nadpisuje, lecz odmawia z konfliktami).  
> **FIX-S28-38:** Tnsnames PRIM musi mieć `LOAD_BALANCE=off` + `FAILOVER=on` (NIE `LOAD_BALANCE=on`). Active Duplicate w 26ai z RAC primary wymaga deterministycznego connecta do jednej instancji — AUX kanały robią RPC back do TARGET, a load-balanced alias trafia na różne nody RAC → `ORA-01138: database must either be open in this instance or not at all` podczas `DBMS_BACKUP_RESTORE.RESTORESETPIECE` (sygnał niespójności state PRIM1/PRIM2 widziany przez DBMS_BACKUP_RESTORE). Pin do prim01, fallback na prim02 jeśli prim01 down. Wzorzec znany z VMs/FIXES_LOG FIX-085.

```bash
# Na prim01 jako oracle — RMAN łączy się przez wallet do primary i bezpośrednio do auxiliary
RMAN_AUX="(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=stby01.lab.local)(PORT=1521))(CONNECT_DATA=(SID=STBY)(UR=A)))"
TNS_ADMIN=~/tns_dgmgrl rman \
    target "/@PRIM" \
    auxiliary "sys/Oracle26ai_LAB!@\"$RMAN_AUX\""
```
```rman
DUPLICATE TARGET DATABASE FOR STANDBY FROM ACTIVE DATABASE
NOFILENAMECHECK
SPFILE
  SET db_unique_name = 'STBY'
  SET cluster_database = 'FALSE'
  SET db_file_name_convert = '+DATA/PRIM/','/u02/oradata/STBY/','+RECO/PRIM/','/u03/fra/STBY/'
  SET log_file_name_convert = '+DATA/PRIM/','/u02/oradata/STBY/','+RECO/PRIM/','/u03/fra/STBY/'
  SET db_create_file_dest = '/u02/oradata/STBY'
  SET db_recovery_file_dest = '/u03/fra/STBY'
  SET db_recovery_file_dest_size = '14G'
  SET control_files = '/u02/oradata/STBY/control01.ctl','/u03/fra/STBY/control02.ctl'
  SET sga_target = '2048M'
  SET pga_aggregate_target = '512M'
  SET dg_broker_start = 'TRUE'
  SET remote_listener = ''
  SET local_listener = '(ADDRESS=(PROTOCOL=TCP)(HOST=stby01.lab.local)(PORT=1521))'
  SET fal_server = 'PRIM'
  SET fal_client = 'STBY'
  SET standby_file_management = 'AUTO'
  SET use_large_pages = 'FALSE';
```

**Krok 6b — Post-RMAN setup na stby01 (FIX-041)**

```bash
# FIX-041: cluster_database_instances i instance_number NIE mogą być w RMAN SET clause
# (RMAN-06581 w 26ai) — ustawiamy przez ALTER SYSTEM po RMAN Duplicate
ssh oracle@stby01 "
export ORACLE_SID=STBY
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=\$ORACLE_HOME/bin:\$PATH
sqlplus -s / as sysdba <<SQL
WHENEVER SQLERROR CONTINUE;
-- ORA-02065 w SI (cluster_database=FALSE) — zignoruj, instance_number wystarczy
ALTER SYSTEM SET cluster_database_instances=1 SCOPE=SPFILE;
WHENEVER SQLERROR EXIT FAILURE;
ALTER SYSTEM SET instance_number=1 SCOPE=SPFILE;
ALTER SYSTEM REGISTER;
EXIT;
SQL
"
```

**Krok 6c — Standby Redo Logs (SRL) na STBY**

> **FIX-S28-43:** Real-time apply + FSFO wymagają SRL na standby. Bez SRL transport idzie tylko po archiwizacji → Apply Lag rośnie liniowo, FSFO odmawia ENABLE. **6 SRL = 3 per thread × 2 thready RAC PRIM**, każdy o rozmiarze ORL (200M default DBCA). stby01 nie ma ASM — pliki w XFS `/u02/oradata/STBY/onlinelog/`.

```bash
ssh oracle@stby01 "
export ORACLE_SID=STBY
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=\$ORACLE_HOME/bin:\$PATH
sqlplus -s / as sysdba <<SQL
ALTER SYSTEM SET standby_file_management=MANUAL SCOPE=BOTH;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 1 GROUP 11 '/u02/oradata/STBY/onlinelog/srl_t1g11.log' SIZE 200M;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 1 GROUP 12 '/u02/oradata/STBY/onlinelog/srl_t1g12.log' SIZE 200M;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 1 GROUP 13 '/u02/oradata/STBY/onlinelog/srl_t1g13.log' SIZE 200M;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 2 GROUP 21 '/u02/oradata/STBY/onlinelog/srl_t2g21.log' SIZE 200M;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 2 GROUP 22 '/u02/oradata/STBY/onlinelog/srl_t2g22.log' SIZE 200M;
ALTER DATABASE ADD STANDBY LOGFILE THREAD 2 GROUP 23 '/u02/oradata/STBY/onlinelog/srl_t2g23.log' SIZE 200M;
ALTER SYSTEM SET standby_file_management=AUTO SCOPE=BOTH;
EXIT;
SQL
"
```

**Krok 6d — DGMGRL: CREATE CONFIGURATION + ADD DATABASE + ENABLE**

```bash
TNS_ADMIN=~/tns_dgmgrl dgmgrl /@PRIM
```
```sql
CREATE CONFIGURATION fsfo_cfg AS PRIMARY DATABASE IS PRIM CONNECT IDENTIFIER IS "PRIM";
ADD DATABASE STBY AS CONNECT IDENTIFIER IS "STBY";
-- FIX-096: StaticConnectIdentifier z PORT=1522 (DGMGRL listener na nodach).
EDIT DATABASE 'stby' SET PROPERTY 'StaticConnectIdentifier'='(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=stby01.lab.local)(PORT=1522))(CONNECT_DATA=(SERVICE_NAME=STBY_DGMGRL.lab.local)(INSTANCE_NAME=STBY)(SERVER=DEDICATED)))';
EDIT INSTANCE 'PRIM1' ON DATABASE 'PRIM' SET PROPERTY 'StaticConnectIdentifier'='(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=prim01.lab.local)(PORT=1522))(CONNECT_DATA=(SERVICE_NAME=PRIM_DGMGRL.lab.local)(INSTANCE_NAME=PRIM1)(SERVER=DEDICATED)))';
EDIT INSTANCE 'PRIM2' ON DATABASE 'PRIM' SET PROPERTY 'StaticConnectIdentifier'='(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=prim02.lab.local)(PORT=1522))(CONNECT_DATA=(SERVICE_NAME=PRIM_DGMGRL.lab.local)(INSTANCE_NAME=PRIM2)(SERVER=DEDICATED)))';
ENABLE CONFIGURATION;
SHOW CONFIGURATION;
EXIT;
```

**Krok 6e — MaxAvailability + LogXptMode=SYNC (FIX-S28-51)**

> Wymagane dla **Zero Data Loss** — zgodnie z `setup_observer.sh` ustawiającym `FastStartFailoverLagLimit=0`, broker musi pracować w `MaxAvailability` z `SYNC` redo transport. Bez tego ASYNC apply ma zawsze pewny lag → FSFO blokowany przy każdej awarii. Architektura w `docs/01` i scenariusz 4 w `docs/09` zakładają tę konfigurację.

```bash
sleep 5  # broker stabilizuje się po ENABLE CONFIGURATION
TNS_ADMIN=~/tns_dgmgrl dgmgrl /@PRIM <<'EOF'
EDIT DATABASE 'PRIM' SET PROPERTY 'LogXptMode'='SYNC';
EDIT DATABASE 'stby' SET PROPERTY 'LogXptMode'='SYNC';
EDIT CONFIGURATION SET PROTECTION MODE AS MAXAVAILABILITY;
SHOW CONFIGURATION;
EXIT
EOF
# Oczekiwane: Protection Mode: MaxAvailability, Configuration Status: SUCCESS
```

---

## 3. Weryfikacja

Po ukończeniu tworzenia Standby, będąc nadal na `prim01` (jako oracle), wykonaj wywołanie DGMGRL, aby sprawdzić stan naszej topologii:

```bash
dgmgrl sys/Oracle26ai_LAB!@PRIM
```

W wierszu DGMGRL wydaj komendę:
```text
DGMGRL> SHOW CONFIGURATION;
```

Oczekiwany rezultat powienien wyglądać w ten sposób (Status: SUCCESS):
```text
Configuration - fsfo_cfg

  Protection Mode: MaxPerformance
  Members:
  PRIM - Primary database
    STBY - Physical standby database

Fast-Start Failover:  Disabled

Configuration Status:
SUCCESS   (status updated 15 seconds ago)
```

Gdy zobaczysz taki status, oznacza to, że Redo Transport przesyła dane na bieżąco, a Standby aplikuje je u siebie. 

Możesz też zweryfikować to łącząc się bezpośrednio na bazę `stby01`:
```bash
ssh oracle@stby01
sqlplus / as sysdba
```
```sql
SELECT open_mode, database_role FROM v$database;
```
Baza Standby będzie znajdować się w roli `PHYSICAL STANDBY` z trybem `READ ONLY WITH APPLY` (Active Data Guard).

---

## Konfiguracja trwała Active Data Guard (READ ONLY WITH APPLY przeżywa STARTUP)

> **Cel:** STBY ma **zawsze** otwierać się w `READ ONLY WITH APPLY` (Real-Time Query), również po reboot stby01 i po `SWITCHOVER TO PRIM` (gdy jest reinstalowany jako standby). Bez tego operator po każdym restarcie musi ręcznie `ALTER DATABASE OPEN READ ONLY` (rozjazd vs ścieżka automatyczna).
>
> **Wymagana licencja:** Active Data Guard option (zob. `01_Architektura` sekcja 4.1).

W ścieżce automatycznej `create_standby_broker.sh` wykonuje to samodzielnie (krok 7). Manualnie:

```bash
# 1. Broker APPLY-OFF - musimy zatrzymac MRP, by zapisac stan PDB-ow.
#    Z infra01 (gdzie wallet SSO):
ssh oracle@infra01 "dgmgrl -silent /@PRIM_ADMIN 'EDIT DATABASE stby SET STATE=APPLY-OFF'"

# 2. Otworz CDB + wszystkie PDB w READ ONLY i ZAPISZ stan.
#    Bezposrednio na stby01 (jako oracle):
ssh oracle@stby01 ". ~/.bash_profile && sqlplus -s / as sysdba <<EOF
-- Jesli MOUNTED, otworz w READ ONLY.
DECLARE
    v_mode VARCHAR2(20);
BEGIN
    SELECT open_mode INTO v_mode FROM v\\\$database;
    IF v_mode = 'MOUNTED' THEN
        EXECUTE IMMEDIATE 'ALTER DATABASE OPEN READ ONLY';
    END IF;
END;
/

ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY;
-- SAVE STATE: zapis trwaly - po kazdym STARTUP PDB wraca w READ ONLY automatycznie.
ALTER PLUGGABLE DATABASE ALL SAVE STATE;
EXIT
EOF"

# FIX-S28-64: Modernizacja - rejestracja PDB jako CRS resource policy=AUTOMATIC + role=PRIMARY.
# W 26ai jest `srvctl modify pdb` (PDB jako CRS resource). Po tym CRS sam otwiera APPPDB
# w READ WRITE przy każdym startup gdy `database_role='PRIMARY'`. W standby roli CRS
# pozostawia PDB - Active DG sam zarządza READ ONLY.
# Bez tego: po każdym switchover/failover trzeba ręcznie ALTER PLUGGABLE DATABASE OPEN
# READ WRITE + SAVE STATE (relikt poprzedniej roli pozostaje).
ssh oracle@prim01 ". ~/.bash_profile && srvctl modify pdb -db PRIM -pdb APPPDB -policy AUTOMATIC -role PRIMARY"
ssh oracle@stby01 ". ~/.bash_profile && srvctl modify pdb -db STBY -pdb APPPDB -policy AUTOMATIC -role PRIMARY"
# Weryfikacja:
ssh oracle@prim01 "srvctl config pdb -db PRIM -pdb APPPDB | grep -E 'Management|role'"
# Oczekiwane:
#   Management policy: AUTOMATIC
#   Pluggable database role: PRIMARY

# FIX-S28-48: Upewnij się że CSSD na stby01 jest ONLINE.
# CRS_SWONLY install + roothas.pl NIE auto-startuje CSSD po boot. Bez CSSD srvctl
# rzuca PRCR-1055 "Cluster membership check failed for node stby01".
ssh root@stby01 "/u01/app/23.26/grid/bin/crsctl check css 2>&1 | grep -q 'is online' || \
    /u01/app/23.26/grid/bin/crsctl start resource ora.cssd -init"
sleep 15
ssh root@stby01 "/u01/app/23.26/grid/bin/crsctl check css"
# Oczekiwane: CRS-4529: Cluster Synchronization Services is online

# FIX-S28-46: Rejestracja STBY w HAS (Oracle Restart) na stby01.
# RMAN DUPLICATE NIE rejestruje bazy w HAS automatycznie. Bez tego kroku:
#   - srvctl status -db STBY → PRCD-1120 / PRCR-1001
#   - srvctl modify (ponizej) rzuca PRCD-1120 — startoption nie zostaje ustawiony
#   - po reboot stby01 baza nie wstaje, crsctl stat res -t pokazuje tylko ora.evmd + ora.ons
ssh oracle@stby01 "srvctl add database -db STBY \
    -oraclehome /u01/app/oracle/product/23.26/dbhome_1 \
    -spfile /u01/app/oracle/product/23.26/dbhome_1/dbs/spfileSTBY.ora \
    -role PHYSICAL_STANDBY \
    -startoption MOUNT \
    -policy AUTOMATIC \
    -domain lab.local"
ssh oracle@stby01 "srvctl config database -db STBY"
# Oczekiwane: pelny dump konfiguracji bazy w HAS (Database name: STBY, Role: PHYSICAL_STANDBY...)

# 3. Oracle Restart startoption - po reboocie stby01 baza otwiera sie od razu w RO
#    (zamiast default 'mount' dla PHYSICAL_STANDBY).
ssh oracle@stby01 "srvctl modify database -db STBY -startoption 'READ ONLY'"
ssh oracle@stby01 "srvctl config database -db STBY | grep -i 'Start option'"
# Oczekiwane: Start option: read only

# FIX-S28-47: Handoff bazy do HAS. Po srvctl add baza nadal chodzi spoza HAS — crsctl
# pokazuje `ora.stby.db OFFLINE OFFLINE` mimo działającej instancji. Trzeba shutdown +
# srvctl start żeby HAS przejął kontrolę (inaczej po pierwszym reboot stby01 baza nie wstanie).
ssh oracle@infra01 "dgmgrl -silent /@PRIM_ADMIN 'EDIT DATABASE stby SET STATE=APPLY-OFF'"
sleep 5
ssh oracle@stby01 ". ~/.bash_profile && sqlplus -s / as sysdba <<<'SHUTDOWN IMMEDIATE'"
ssh oracle@stby01 "srvctl start database -db STBY"
sleep 10

# Sanity check — teraz HAS powinno pokazać ONLINE ONLINE
ssh grid@stby01 "crsctl stat res ora.stby.db -t"
# Oczekiwane: ora.stby.db ONLINE ONLINE stby01 Open Read Only,STABLE

# 4. Broker APPLY-ON - wznawiamy Redo Apply, baza w trybie Real-Time Query pod HAS.
ssh oracle@infra01 "dgmgrl -silent /@PRIM_ADMIN 'EDIT DATABASE stby SET STATE=APPLY-ON'"
```

### Weryfikacja konfiguracji Active DG

```bash
ssh oracle@stby01 ". ~/.bash_profile && sqlplus -s / as sysdba <<'EOF'
SELECT name, open_mode, database_role FROM v\$database;
SELECT name, open_mode FROM v\$pdbs WHERE name <> 'PDB\$SEED';
EXIT
EOF"
# Oczekiwane:
#   STBY / READ ONLY WITH APPLY / PHYSICAL STANDBY
#   APPPDB / READ ONLY
```

```bash
# Test odpornosci na restart - baza ma wrocic w READ ONLY WITH APPLY.
ssh oracle@stby01 "srvctl stop database -db STBY && srvctl start database -db STBY"
ssh oracle@stby01 ". ~/.bash_profile && sqlplus -s / as sysdba <<<\"SELECT open_mode FROM v\\\$database;\""
# READ ONLY WITH APPLY    <- bez recznych komend, dzieki SAVE STATE + startoption
```

> 💡 Po `SWITCHOVER TO PRIM` (Scenariusz 1 w docs/09) STBY wraca w roli PHYSICAL_STANDBY, a `SAVE STATE` + `startoption=READ ONLY` zapewniają, że broker NIE prosi operatora o `STARTUP`. To kluczowe dla automatyzacji testów switchover (rozjazd vs manual znika).

---
**Następny krok:** `07_FSFO_Observers_PL.md`

