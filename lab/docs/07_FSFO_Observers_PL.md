> [🇬🇧 English](./07_FSFO_Observers.md) | 🇵🇱 Polski

# 07 — Instalacja i Konfiguracja FSFO Observer (VMs2-install)

> **Cel:** Zainstalowanie klienta Oracle (23.26.1 / 26ai) na środowisku zewnętrznym (`infra01`), wdrożenie bezhasłowego autoryzowania typu Wallet SSO (Auto-Login), oraz rejestracja procesu `observer` pilnującego dostępności środowiska Data Guard i wyzwalającego w razie awarii automatyczny failover (Fast-Start Failover - FSFO).

W tej sekcji szczególnie ważna jest kompatybilność, ponieważ wydanie 26ai przynosi fundamentalne różnice w obsłudze Brokera, systemd i uwierzytelniania względem 19c.

---

## Metoda 1: Szybka Ścieżka Automatyczna (Zalecana)

Zautomatyzowany skrypt omija wszelkie pułapki (tzw. "FIXy") wprowadzone w najnowszym Oracle 26ai (brak flagi security w rsp, odpowiedni wpis sqlnet.ora dla wallet, zaktualizowana struktura `START OBSERVER` w systemd bez pętli).

> **Pre-req:** pliki z repo skopiowane do `/tmp/` na każdym z 3 hostów (infra01/prim01/stby01) przez MobaXterm SCP:
> - `<repo>/scripts/` → `/tmp/scripts/`
> - `<repo>/response_files/` → `/tmp/response_files/` (tylko infra01, dla `client.rsp`)

### Krok 1.1 — Master Observer `obs_ext` na infra01

Zaloguj się na **`infra01`** jako **`root`**:
```bash
ls /tmp/scripts/setup_observer.sh /tmp/response_files/client.rsp

# Defaults: OBSERVER_ROLE=master, OBSERVER_NAME=obs_ext, OBSERVER_HOST=infra01.lab.local
bash /tmp/scripts/setup_observer.sh
```

Skrypt wykonuje całość (Kroki 1-6 z Metody 2) jednym przebiegiem — instalacja Oracle Client, TNS, wallet z 4 credentials (PRIM_ADMIN/STBY_ADMIN/PRIM/STBY), wrappery start/stop, unit systemd, ENABLE FAST_START FAILOVER, FSFO properties.

### Krok 1.2 — Backup Observer `obs_dc` na prim01

Zaloguj się na **`prim01`** jako **`root`**:
```bash
OBSERVER_ROLE=backup \
OBSERVER_NAME=obs_dc \
OBSERVER_HOST=prim01.lab.local \
ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1 \
bash /tmp/scripts/setup_observer.sh
```

Backup observer używa istniejącego DB_HOME (nie potrzeba instalować Oracle Client). Skrypt tworzy `/etc/oracle/{tns,wallet}/obs_dc`, wrappery, unit `dgmgrl-observer-obs_dc.service`, lokalny wallet z credentials.

### Krok 1.3 — Backup Observer `obs_dr` na stby01

Zaloguj się na **`stby01`** jako **`root`**:
```bash
OBSERVER_ROLE=backup \
OBSERVER_NAME=obs_dr \
OBSERVER_HOST=stby01.lab.local \
ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1 \
bash /tmp/scripts/setup_observer.sh
```

### Krok 1.4 — Weryfikacja redundancji

Z dowolnego hosta jako `oracle`:
```bash
TNS_ADMIN=/etc/oracle/tns/obs_ext dgmgrl /@PRIM_ADMIN "SHOW OBSERVERS"
# (na prim01/stby01 użyj /etc/oracle/tns/obs_dc lub obs_dr)
```

Oczekiwany output — **3 obserwerów**, jeden `Active`, dwóch `Standby`:
```
Configuration - fsfo_cfg
  Primary:            PRIM
  Active Target:      stby
  Active Observer:    obs_ext
  ...
Observer "obs_ext" - Master
  Host Name: infra01.lab.local
  Last Ping to Primary: ... seconds ago
Observer "obs_dc" - Backup
  Host Name: prim01.lab.local
Observer "obs_dr" - Backup
  Host Name: stby01.lab.local
```

Po sukcesie przejdź bezpośrednio do **2. Weryfikacja Działania**.

---

## Metoda 2: Ścieżka Manualna (Krok po kroku)

Dla osób chcących zobaczyć jak działa konfiguracja Observera pod najnowszym systemem 26ai krok po kroku.

### Krok 1: Przygotowanie użytkownika i powłoki

Zaloguj się na **`infra01`** jako użytkownik **`root`**:

```bash
# Utworzenie ról oinstall, dba
groupadd -g 54321 oinstall 2>/dev/null || true
groupadd -g 54322 dba 2>/dev/null || true
groupadd -g 54325 dgdba 2>/dev/null || true
useradd -u 54322 -g oinstall -G dba,dgdba oracle 2>/dev/null || true
echo "oracle:Oracle26ai_LAB!" | chpasswd

mkdir -p /u01/app/oracle/product/23.26/client_1
mkdir -p /u01/app/oraInventory
chown -R oracle:oinstall /u01/app
chmod -R 775 /u01/app
```

### Krok 2: Instalacja Oracle Client 26ai

```bash
# Jako oracle na infra01
su - oracle
mkdir -p /tmp/client
cd /tmp/client

# Rozpakowanie instalatora
unzip -q /mnt/oracle_binaries/V1054587-01-OracleDatabaseClient23.26.1.0.0forLinux_x86-64.zip

# Instalacja cicha w trybie "Administrator" (posiada potrzebne nam mkstore i dgmgrl)
# UWAGA (S28-52): Schema rspfmt_clientinstall_response_schema_v23.0.0 w 26ai jest STRICT.
# Akceptowane klucze: oracle.install.responseFileVersion, UNIX_GROUP_NAME, INVENTORY_LOCATION,
# ORACLE_HOME, ORACLE_BASE, oracle.install.client.installType. Każdy nadmiarowy klucz
# (np. oracle.install.option, executeRootScript, DECLINE_SECURITY_UPDATES) -> INS-10105.
# Patrz response_files/client.rsp v2.2 oraz VMs/FIXES_LOG FIX-070.
./client/runInstaller -silent -responseFile /tmp/response_files/client.rsp -ignorePrereqFailure
```

Po zakończeniu instalatora wróć na konto ROOT (lub z drugiego okna terminala) i wykonaj skrypt postinstalacyjny:
```bash
# Jako root
/u01/app/oraInventory/orainstRoot.sh
```

Wróć na konto `oracle` i uaktualnij zmienne środowiskowe:
```bash
# Jako oracle na infra01
cat >> /home/oracle/.bash_profile <<'EOF'
export ORACLE_HOME=/u01/app/oracle/product/23.26/client_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:/usr/lib
export TNS_ADMIN=/etc/oracle/tns/obs_ext
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
export NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS'
umask 022
EOF

source /home/oracle/.bash_profile
```

### Krok 3: TNSNAMES oraz SQLNET (Specyfika 26ai)

Utwórz odpowiednią strukturę na logi, poświadczenia i tnsnames:

```bash
# Jako root (i oddaj uprawnienia użytkownikowi oracle)
mkdir -p /etc/oracle/tns/obs_ext
mkdir -p /etc/oracle/wallet/obs_ext
mkdir -p /var/log/oracle/obs_ext

chown -R oracle:oinstall /etc/oracle/tns
chown -R oracle:oinstall /etc/oracle/wallet
chown -R oracle:oinstall /var/log/oracle
chmod -R 755 /etc/oracle/tns
chmod -R 700 /etc/oracle/wallet
chmod -R 755 /var/log/oracle
```

Teraz skonfiguruj wpisy połączeniowe do baz danych:

```bash
# Jako oracle na infra01
cat > /etc/oracle/tns/obs_ext/tnsnames.ora <<'EOF'
# FIX-040 / S28-29: SERVICE_NAME musi mieć suffix .lab.local — Oracle 23.26.1 z db_domain=lab.local
# rejestruje serwisy jako NAZWA.lab.local. Bez suffixu → ORA-12514.
# FIX-S28-38: LOAD_BALANCE=off + FAILOVER=on (deterministic connect, fallback failover).
# _ADMIN aliasy: port 1522 (LISTENER_DGMGRL) — używane przez `dgmgrl /@PRIM_ADMIN` (broker control).
PRIM_ADMIN =
  (DESCRIPTION =
    (ADDRESS_LIST =
      (LOAD_BALANCE = off)
      (FAILOVER = on)
      (ADDRESS = (PROTOCOL = TCP)(HOST = prim01.lab.local)(PORT = 1522))
      (ADDRESS = (PROTOCOL = TCP)(HOST = prim02.lab.local)(PORT = 1522))
    )
    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = PRIM_DGMGRL.lab.local)(UR = A))
  )
STBY_ADMIN =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = stby01.lab.local)(PORT = 1522))
    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = STBY_DGMGRL.lab.local)(UR = A))
  )

# S28-56: aliasy PRIM/STBY = DGConnectIdentifier observera. Po START OBSERVER, broker
# zwraca observerowi DGConnectIdentifier (default = db_unique_name) i observer próbuje
# `connect /@PRIM` oraz `connect /@STBY`. Bez tych aliasów ORA-12154 w log observera.
# Port 1521 (LISTENER), SERVICE_NAME = db_unique_name.lab.local.
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
```

A teraz to co najważniejsze: parametr SQLNET dla portfela Oracle 26ai (FIX-072):

```bash
cat > /etc/oracle/tns/obs_ext/sqlnet.ora <<'EOF'
WALLET_LOCATION = (SOURCE = (METHOD = FILE) (METHOD_DATA = (DIRECTORY = /etc/oracle/wallet/obs_ext)))
SQLNET.WALLET_OVERRIDE = TRUE
# FIX-072: Musi być (NONE), by nie wymusić uwierzytelniania NTS zamiast z lokalnego pliku Wallet
SQLNET.AUTHENTICATION_SERVICES = (NONE)
SQLNET.EXPIRE_TIME = 1
EOF
```

### Krok 4: Tworzenie Wallet Auto-Login

Observer używa portfela, aby logować się jako "SYS" bez wpisywania haseł.

**Wariant interaktywny** — instalator wyświetli prompt na hasło (wpisz `Oracle26ai_LAB!`):

```bash
# Jako oracle na infra01
mkstore -wrl /etc/oracle/wallet/obs_ext -create
# Enter password: Oracle26ai_LAB!
# Enter password again: Oracle26ai_LAB!

mkstore -wrl /etc/oracle/wallet/obs_ext -createCredential PRIM_ADMIN sys 'Oracle26ai_LAB!'
# Enter wallet password: Oracle26ai_LAB!

mkstore -wrl /etc/oracle/wallet/obs_ext -createCredential STBY_ADMIN sys 'Oracle26ai_LAB!'
# Enter wallet password: Oracle26ai_LAB!

# UWAGA (S28-53): w 26ai mkstore tworzy cwallet.sso AUTOMATYCZNIE przy `-create`,
# więc `-autoLogin` / `-createSSO` jest opcjonalne. Sprawdź:
ls -la /etc/oracle/wallet/obs_ext/    # → cwallet.sso, ewallet.p12
```

**Wariant nieinteraktywny** — pwd przez stdin (zalecane do skryptów, idempotentny):

```bash
# Jako oracle na infra01
WP='Oracle26ai_LAB!'
WL='/etc/oracle/wallet/obs_ext'

# 1. Wallet — skip jesli juz istnieje
if [ ! -f "$WL/cwallet.sso" ]; then
    printf '%s\n%s\n' "$WP" "$WP" | mkstore -wrl "$WL" -create -nologo
fi

# 2. Helper idempotent (list -> create OR modify)
ensure_cred() {
    local ALIAS=$1
    # -qw (word-boundary) — bez tego grep "PRIM" łapie też "PRIM_ADMIN" (S28-57-bis)
    if printf '%s\n' "$WP" | mkstore -wrl "$WL" -listCredential -nologo 2>/dev/null | grep -qw "$ALIAS"; then
        printf '%s\n' "$WP" | mkstore -wrl "$WL" -modifyCredential "$ALIAS" sys "$WP" -nologo
    else
        printf '%s\n' "$WP" | mkstore -wrl "$WL" -createCredential "$ALIAS" sys "$WP" -nologo
    fi
}

ensure_cred PRIM_ADMIN
ensure_cred STBY_ADMIN
# S28-57: PRIM/STBY aliasy też muszą być w wallet — observer po START loguje się
# do PRIM/STBY (DGConnectIdentifier), bez credential → DGM-16979 Authentication failed.
ensure_cred PRIM
ensure_cred STBY
```

> **Pułapka (S28-53 / FIX-071 z VMs):** flaga `-p <pwd>` w `mkstore -create` w 26ai NIE działa — tool i tak prosi interaktywnie. Jeśli skrypt podaje `-p ""` (np. po `su -p oracle <<'EOF'` z apostrofami blokującymi ekspansję), dostaniesz `PKI-01003: Passwords did not match` po kilku timeoutach. Zawsze używaj stdin (heredoc bez apostrofów).

### Krok 5: Konfiguracja SystemD i start Observera

Aby observer działał w tle, utworzymy usługę `systemd`. Wersja 26ai (FIX-074, FIX-075) zabrania parametru `-logfile` na zewnątrz procesu i korzystania z `IN BACKGROUND` przy `Type=simple`.

> **Pułapka (S28-54):** `START OBSERVER ... FILE IS '...' LOGFILE IS '...'` zawiera apostrofy. Wpisanie tego bezpośrednio w `ExecStart=` daje `status=203/EXEC` (parser systemd nie radzi sobie z embedded single-quotes w double-quoted argument). Rozwiązanie: wrapper script `/usr/local/bin/start-observer-obs_ext.sh` który używa `bash` (gdzie quoting działa) i `exec dgmgrl ...`.

**Krok 5a — Wrapper scripts (jako root):**

```bash
cat > /usr/local/bin/start-observer-obs_ext.sh <<'EOF'
#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/23.26/client_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib
export TNS_ADMIN=/etc/oracle/tns/obs_ext
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
exec $ORACLE_HOME/bin/dgmgrl -echo /@PRIM_ADMIN "START OBSERVER obs_ext FILE IS '/var/log/oracle/obs_ext/obs_ext.dat' LOGFILE IS '/var/log/oracle/obs_ext/obs_ext.log'"
EOF

cat > /usr/local/bin/stop-observer-obs_ext.sh <<'EOF'
#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/23.26/client_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib
export TNS_ADMIN=/etc/oracle/tns/obs_ext
exec $ORACLE_HOME/bin/dgmgrl /@PRIM_ADMIN "STOP OBSERVER obs_ext"
EOF

chmod 755 /usr/local/bin/start-observer-obs_ext.sh /usr/local/bin/stop-observer-obs_ext.sh
```

**Krok 5b — Unit systemd:**

```bash
# Jako root
cat > /etc/systemd/system/dgmgrl-observer-obs_ext.service <<'EOF'
[Unit]
Description=Oracle Data Guard Observer obs_ext (FSFO master)
After=network-online.target chronyd.service

[Service]
Type=simple
User=oracle
Group=oinstall
WorkingDirectory=/var/log/oracle/obs_ext

ExecStart=/usr/local/bin/start-observer-obs_ext.sh
ExecStop=/usr/local/bin/stop-observer-obs_ext.sh

Restart=on-failure
RestartSec=10s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now dgmgrl-observer-obs_ext
```

### Krok 6: Aktywacja Fast-Start Failover (FSFO)

Po 15-tu sekundach, Observer połączy się w pełni do konfiguracji. Pozostało tylko aktywować tryb FSFO na poziomie brokera.
(Z uwzględnieniem FIX-077 narzucającego `FastStartFailoverLagLimit=0` by wymusić Zero Data Loss).

> **F-22 — Threshold vs LagLimit (zrozum różnicę przed zmianą):**
> - `FastStartFailoverThreshold=30` → ile sekund Observer + Standby czekają na ożywienie Primary, zanim wyzwolą failover. Niżej = szybszy failover, ale więcej fałszywych alarmów (np. krótka przerwa sieciowa).
> - `FastStartFailoverLagLimit=0` → maksymalny dopuszczalny **apply lag** standby w momencie failoveru.  
>   - `0` = **Zero Data Loss** (wymaga **MaxAvailability** / SYNC); FSFO blokuje failover jeśli standby zostało za primary z apply.  
>   - `> 0` (np. 30 s) = "Potential Data Loss" mode, dla **MaxPerformance** / ASYNC; akceptujemy potencjalną utratę 30 s redo, by failover mógł się odbyć.  
> Konfiguracja w LAB-ie używa SYNC + `LagLimit=0`. Przed zmianą w produkcji potwierdź tryb DG Protection (`SHOW CONFIGURATION` → `Protection Mode`) i konsekwencje RPO.

```bash
# Jako oracle
dgmgrl /@PRIM_ADMIN
```
```sql
EDIT CONFIGURATION SET PROPERTY FastStartFailoverThreshold=30;
EDIT CONFIGURATION SET PROPERTY FastStartFailoverLagLimit=0;
EDIT CONFIGURATION SET PROPERTY FastStartFailoverAutoReinstate=TRUE;
EDIT CONFIGURATION SET PROPERTY ObserverOverride=TRUE;

ENABLE FAST_START FAILOVER;
EXIT;
```

---

## 6. Wdrożenie Backup Observerów (`obs_dc` + `obs_dr`) — KROK PO KROKU

> **Uzasadnienie:** Master Observer (`obs_ext`) jest jednym punktem awarii. Architektura w `01_Architecture_and_Assumptions_PL.md` zakłada redundancję — `obs_dc` na `prim01` i `obs_dr` na `stby01`. W razie awarii `infra01` jeden z Backup Observerów automatycznie przejmuje rolę Active w czasie ~10–60 s.

> **Kluczowy warunek:** Backup Observer musi mieć tę samą wersję `dgmgrl` co Master. Na prim01/stby01 NIE instalujemy Oracle Client — używamy istniejącego `dgmgrl` z DB Home (`/u01/app/oracle/product/23.26/dbhome_1/bin/dgmgrl`).

> **Schemat:** poniższa procedura jest analogiczna dla obu obserwerów. Różnice — tylko nazwa (`obs_dc` vs `obs_dr`) i host (`prim01` vs `stby01`).

### Krok 6.1 — Backup Observer `obs_dc` na `prim01`

**6.1.a — Katalogi (root@prim01):**
```bash
mkdir -p /etc/oracle/tns/obs_dc /etc/oracle/wallet/obs_dc /var/log/oracle/obs_dc
chown -R oracle:oinstall /etc/oracle/tns/obs_dc /etc/oracle/wallet/obs_dc /var/log/oracle/obs_dc
chmod 700 /etc/oracle/wallet/obs_dc
chmod 755 /etc/oracle/tns/obs_dc /var/log/oracle/obs_dc
```

**6.1.b — tnsnames.ora i sqlnet.ora (oracle@prim01):**
```bash
cat > /etc/oracle/tns/obs_dc/tnsnames.ora <<'EOF'
PRIM_ADMIN =
  (DESCRIPTION =
    (ADDRESS_LIST =
      (LOAD_BALANCE = off)
      (FAILOVER = on)
      (ADDRESS = (PROTOCOL = TCP)(HOST = prim01.lab.local)(PORT = 1522))
      (ADDRESS = (PROTOCOL = TCP)(HOST = prim02.lab.local)(PORT = 1522))
    )
    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = PRIM_DGMGRL.lab.local)(UR = A))
  )
STBY_ADMIN =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = stby01.lab.local)(PORT = 1522))
    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = STBY_DGMGRL.lab.local)(UR = A))
  )
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

cat > /etc/oracle/tns/obs_dc/sqlnet.ora <<'EOF'
WALLET_LOCATION = (SOURCE = (METHOD = FILE) (METHOD_DATA = (DIRECTORY = /etc/oracle/wallet/obs_dc)))
SQLNET.WALLET_OVERRIDE = TRUE
SQLNET.AUTHENTICATION_SERVICES = (NONE)
SQLNET.EXPIRE_TIME = 1
EOF
```

**6.1.c — Wallet z 4 credentials (oracle@prim01):**
```bash
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export TNS_ADMIN=/etc/oracle/tns/obs_dc

WP='Oracle26ai_LAB!'
WL='/etc/oracle/wallet/obs_dc'

if [ ! -f "$WL/cwallet.sso" ]; then
    printf '%s\n%s\n' "$WP" "$WP" | mkstore -wrl "$WL" -create -nologo
fi

ensure_cred() {
    local ALIAS=$1
    if printf '%s\n' "$WP" | mkstore -wrl "$WL" -listCredential -nologo 2>/dev/null | grep -qw "$ALIAS"; then
        printf '%s\n' "$WP" | mkstore -wrl "$WL" -modifyCredential "$ALIAS" sys "$WP" -nologo
    else
        printf '%s\n' "$WP" | mkstore -wrl "$WL" -createCredential "$ALIAS" sys "$WP" -nologo
    fi
}
ensure_cred PRIM_ADMIN
ensure_cred STBY_ADMIN
ensure_cred PRIM
ensure_cred STBY
```

**6.1.d — Wrappery start/stop (root@prim01):**
```bash
cat > /usr/local/bin/start-observer-obs_dc.sh <<'EOF'
#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib
export TNS_ADMIN=/etc/oracle/tns/obs_dc
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
exec $ORACLE_HOME/bin/dgmgrl -echo /@PRIM_ADMIN "START OBSERVER obs_dc FILE IS '/var/log/oracle/obs_dc/obs_dc.dat' LOGFILE IS '/var/log/oracle/obs_dc/obs_dc.log'"
EOF

cat > /usr/local/bin/stop-observer-obs_dc.sh <<'EOF'
#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib
export TNS_ADMIN=/etc/oracle/tns/obs_dc
exec $ORACLE_HOME/bin/dgmgrl /@PRIM_ADMIN "STOP OBSERVER obs_dc"
EOF

chmod 755 /usr/local/bin/start-observer-obs_dc.sh /usr/local/bin/stop-observer-obs_dc.sh
```

**6.1.e — Unit systemd (root@prim01):**
```bash
cat > /etc/systemd/system/dgmgrl-observer-obs_dc.service <<'EOF'
[Unit]
Description=Oracle Data Guard Observer obs_dc (FSFO backup)
After=network-online.target chronyd.service

[Service]
Type=simple
User=oracle
Group=oinstall
WorkingDirectory=/var/log/oracle/obs_dc
ExecStart=/usr/local/bin/start-observer-obs_dc.sh
ExecStop=/usr/local/bin/stop-observer-obs_dc.sh
Restart=on-failure
RestartSec=10s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now dgmgrl-observer-obs_dc
```

> **Uwaga (S28-59):** Backup Observer NIE wykonuje `EDIT CONFIGURATION SET PROPERTY` ani `ADD OBSERVER` — w 26ai broker auto-rejestruje observera przy `START OBSERVER` (wywoływane przez wrapper). Master już Active → broker automatycznie wpisuje go jako Backup. Legacy `ADD OBSERVER ... ON HOST '...'` z 19c rzuca `Syntax error before or at "OBSERVER"` w 26ai.

### Krok 6.2 — Backup Observer `obs_dr` na `stby01`

Procedura analogiczna do 6.1. Wszystkie polecenia wykonywane na **stby01** (nie prim01), nazwa observera to `obs_dr`.

**6.2.a — Katalogi (root@stby01):**
```bash
mkdir -p /etc/oracle/tns/obs_dr /etc/oracle/wallet/obs_dr /var/log/oracle/obs_dr
chown -R oracle:oinstall /etc/oracle/tns/obs_dr /etc/oracle/wallet/obs_dr /var/log/oracle/obs_dr
chmod 700 /etc/oracle/wallet/obs_dr
chmod 755 /etc/oracle/tns/obs_dr /var/log/oracle/obs_dr
```

**6.2.b — tnsnames.ora i sqlnet.ora (oracle@stby01):**
```bash
cat > /etc/oracle/tns/obs_dr/tnsnames.ora <<'EOF'
PRIM_ADMIN =
  (DESCRIPTION =
    (ADDRESS_LIST =
      (LOAD_BALANCE = off)
      (FAILOVER = on)
      (ADDRESS = (PROTOCOL = TCP)(HOST = prim01.lab.local)(PORT = 1522))
      (ADDRESS = (PROTOCOL = TCP)(HOST = prim02.lab.local)(PORT = 1522))
    )
    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = PRIM_DGMGRL.lab.local)(UR = A))
  )
STBY_ADMIN =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = stby01.lab.local)(PORT = 1522))
    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = STBY_DGMGRL.lab.local)(UR = A))
  )
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

cat > /etc/oracle/tns/obs_dr/sqlnet.ora <<'EOF'
WALLET_LOCATION = (SOURCE = (METHOD = FILE) (METHOD_DATA = (DIRECTORY = /etc/oracle/wallet/obs_dr)))
SQLNET.WALLET_OVERRIDE = TRUE
SQLNET.AUTHENTICATION_SERVICES = (NONE)
SQLNET.EXPIRE_TIME = 1
EOF
```

**6.2.c — Wallet z 4 credentials (oracle@stby01):**
```bash
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export TNS_ADMIN=/etc/oracle/tns/obs_dr

WP='Oracle26ai_LAB!'
WL='/etc/oracle/wallet/obs_dr'

if [ ! -f "$WL/cwallet.sso" ]; then
    printf '%s\n%s\n' "$WP" "$WP" | mkstore -wrl "$WL" -create -nologo
fi

ensure_cred() {
    local ALIAS=$1
    if printf '%s\n' "$WP" | mkstore -wrl "$WL" -listCredential -nologo 2>/dev/null | grep -qw "$ALIAS"; then
        printf '%s\n' "$WP" | mkstore -wrl "$WL" -modifyCredential "$ALIAS" sys "$WP" -nologo
    else
        printf '%s\n' "$WP" | mkstore -wrl "$WL" -createCredential "$ALIAS" sys "$WP" -nologo
    fi
}
ensure_cred PRIM_ADMIN
ensure_cred STBY_ADMIN
ensure_cred PRIM
ensure_cred STBY
```

**6.2.d — Wrappery start/stop (root@stby01):**
```bash
cat > /usr/local/bin/start-observer-obs_dr.sh <<'EOF'
#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib
export TNS_ADMIN=/etc/oracle/tns/obs_dr
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
exec $ORACLE_HOME/bin/dgmgrl -echo /@PRIM_ADMIN "START OBSERVER obs_dr FILE IS '/var/log/oracle/obs_dr/obs_dr.dat' LOGFILE IS '/var/log/oracle/obs_dr/obs_dr.log'"
EOF

cat > /usr/local/bin/stop-observer-obs_dr.sh <<'EOF'
#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib
export TNS_ADMIN=/etc/oracle/tns/obs_dr
exec $ORACLE_HOME/bin/dgmgrl /@PRIM_ADMIN "STOP OBSERVER obs_dr"
EOF

chmod 755 /usr/local/bin/start-observer-obs_dr.sh /usr/local/bin/stop-observer-obs_dr.sh
```

**6.2.e — Unit systemd (root@stby01):**
```bash
cat > /etc/systemd/system/dgmgrl-observer-obs_dr.service <<'EOF'
[Unit]
Description=Oracle Data Guard Observer obs_dr (FSFO backup)
After=network-online.target chronyd.service

[Service]
Type=simple
User=oracle
Group=oinstall
WorkingDirectory=/var/log/oracle/obs_dr
ExecStart=/usr/local/bin/start-observer-obs_dr.sh
ExecStop=/usr/local/bin/stop-observer-obs_dr.sh
Restart=on-failure
RestartSec=10s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now dgmgrl-observer-obs_dr
```

### Krok 6.3 — Weryfikacja redundancji

```bash
su - oracle
dgmgrl /@PRIM_ADMIN
```
```text
DGMGRL> SHOW OBSERVERS;

Configuration - fsfo_cfg
   Primary:            PRIM
   Active Target:      STBY

Observer "obs_ext" - Master
   Host Name:                    infra01.lab.local
   Last Ping to Primary:         1 second ago
   Last Ping to Target:          1 second ago

Observer "obs_dc" - Backup
   Host Name:                    prim01.lab.local
   Last Ping to Primary:         2 seconds ago
   Last Ping to Target:          2 seconds ago

Observer "obs_dr" - Backup
   Host Name:                    stby01.lab.local
   Last Ping to Primary:         2 seconds ago
   Last Ping to Target:          2 seconds ago
```

> Po awarii `obs_ext` (np. crash `infra01`), DGMGRL w ciągu 10–60 s podniesie jeden z Backup do statusu **Master**. `SHOW FAST_START FAILOVER` wciąż raporta `ENABLED`. Test scenariusza w `09_Test_Scenarios_PL.md`.

---

## 2. Weryfikacja Działania

Zaloguj się na **`infra01`** (lub jakikolwiek inny węzeł klastra) jako `oracle` i uruchom DGMGRL wykorzystując nowy Wallet SSO (czyli bez podawania hasła w linii poleceń):

```bash
su - oracle
dgmgrl /@PRIM_ADMIN
```

W powłoce `DGMGRL>` wydaj komendę:
```text
DGMGRL> SHOW FAST_START FAILOVER;
```

Oczekiwany wynik powinien jednoznacznie wskazać włączenie mechanizmu i zarejestrowanego Observera:
```text
Fast-Start Failover: ENABLED

  Threshold:           30 seconds
  Target:              STBY
  Observer:            obs_ext
  Lag Limit:           0 seconds
  Shutdown Primary:    TRUE
  Auto-reinstate:      TRUE
  Observer Reconnect:  10 seconds
  Observer Override:   TRUE
```

Pamiętaj, by potwierdzić status całego brokera:
```text
DGMGRL> SHOW CONFIGURATION;
```
Jeżeli `Configuration Status` widnieje jako `SUCCESS` i nie pojawiają się żadne `Warnings` - oznacza to, że Twoja architektura Maximum Availability z FSFO pracuje prawidłowo i w przypadku nagłego `SHUTDOWN ABORT` na `prim01/prim02`, system w przeciągu 30-40 sekund przeniesie role produkcyjne na `stby01`.

---
**Następny krok:** `08_TAC_and_Tests_PL.md`

