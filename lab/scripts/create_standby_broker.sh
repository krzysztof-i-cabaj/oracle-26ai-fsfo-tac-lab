#!/bin/bash
# Skrypt: create_standby_broker.sh / Script: create_standby_broker.sh
# Cel: Automatyczne utworzenie Physical Standby (STBY) przy uzyciu najnowszej funkcjonalnosci / Goal: Automatically create Physical Standby (STBY) using the latest feature
#      Data Guard Broker: CREATE PHYSICAL STANDBY DATABASE. Eliminuje manualne uzycie RMAN. / Data Guard Broker: CREATE PHYSICAL STANDBY DATABASE. Eliminates manual RMAN usage.
# Uruchamiac na: prim01 jako uzytkownik oracle / Run on: prim01 as oracle user

set -euo pipefail

log() { echo "[$(date +%H:%M:%S)] $*"; }

# F-04: LAB_PASS z external secret file lub zmiennej srodowiskowej.
# Plik /root/.lab_secrets musi miec chmod 600 i wpis: export LAB_PASS='haslo'
# F-04: LAB_PASS from external secret file or environment variable.
if [ -r /root/.lab_secrets ]; then
    # shellcheck source=/dev/null
    source /root/.lab_secrets
elif [ -r "$HOME/.lab_secrets" ]; then
    # shellcheck source=/dev/null
    source "$HOME/.lab_secrets"
fi
if [ -z "${LAB_PASS:-}" ]; then
    log "BŁĄD: zmienna LAB_PASS nieustawiona. / ERROR: LAB_PASS not set."
    log "Stworz plik ~/.lab_secrets (chmod 600) z linia: export LAB_PASS='haslo'"
    log "Lub uruchom: LAB_PASS='haslo' bash $0"
    exit 1
fi
PRIM_DB="PRIM"
STBY_DB="STBY"

# F-04: lokalny wallet auto-login dla DGMGRL bez hasel w argumentach procesu.
# F-04: local auto-login wallet for DGMGRL without password leakage in process list.
WALLET_DIR="${WALLET_DIR:-$HOME/wallet/dgmgrl_prim}"
if [ ! -f "$WALLET_DIR/cwallet.sso" ]; then
    log "0. Tworze lokalny wallet auto-login do DGMGRL (haslo SYS) ... / 0. Creating local DGMGRL wallet ..."
    mkdir -p "$WALLET_DIR"
    chmod 700 "$WALLET_DIR"
    # FIX-097: mkstore w 23.26.1 nie akceptuje -p; haslo przez stdin (heredoc).
    # -create: haslo dwa razy (nowe haslo + potwierdzenie).
    mkstore -wrl "$WALLET_DIR" -create -nologo << MKEOF
$LAB_PASS
$LAB_PASS
MKEOF
    # -createCredential: arg3=haslo_credential(SYS), stdin=haslo_wallet.
    mkstore -wrl "$WALLET_DIR" -createCredential PRIM sys "$LAB_PASS" -nologo << MKEOF
$LAB_PASS
MKEOF
    # Credential dla STBY (sqlplus /@STBY w kroku 7 Active DG setup)
    mkstore -wrl "$WALLET_DIR" -createCredential STBY sys "$LAB_PASS" -nologo << MKEOF
$LAB_PASS
MKEOF
    # -createSSO: tworzy cwallet.sso (auto-login); -autoLogin nieistnieje w 23.26.1.
    mkstore -wrl "$WALLET_DIR" -createSSO -nologo << MKEOF
$LAB_PASS
MKEOF
fi
# Override TNS_ADMIN do lokalnego sqlnet.ora wskazujacego na wallet.
# Override TNS_ADMIN with local sqlnet.ora that points to the wallet.
TNS_DIR_LOCAL="${TNS_DIR_LOCAL:-$HOME/tns_dgmgrl}"
mkdir -p "$TNS_DIR_LOCAL"
cat > "$TNS_DIR_LOCAL/sqlnet.ora" <<SQLNETEOF
WALLET_LOCATION = (SOURCE = (METHOD = FILE) (METHOD_DATA = (DIRECTORY = $WALLET_DIR)))
SQLNET.WALLET_OVERRIDE = TRUE
SQLNET.AUTHENTICATION_SERVICES = (NONE)
SQLNETEOF
# Reuze tnsnames.ora z $ORACLE_HOME/network/admin (zostanie uzupelniony w kroku 4).
# Reuse tnsnames.ora from $ORACLE_HOME/network/admin (filled by step 4).

log "=========================================================="
log "    Tworzenie Standby via Data Guard Broker (26ai)        "
log "    Creating Standby via Data Guard Broker (26ai)         "
log "=========================================================="

# ORACLE_SID PRIM1 wymagane przez sqlplus w pre-flight check (0b) i krok 1.
# Po S28-41 .bash_profile uzytkownika oracle ma juz to ustawione, ale wymuszamy
# defensywnie na wypadek run-u nieinterakcyjnego.
export ORACLE_SID=PRIM1

# FIX-S28-44a: Pre-flight sanity check — oba instancje PRIM musza byc OPEN.
# Jesli PRIM2 jest w Mounted (Closed) lub PRIM1 down → ORA-01138 podczas RMAN DUPLICATE.
# Lepiej zatrzymac sie tu niz tracic 30 min na RMAN ktory i tak by sie nie udal.
# FIX-S28-44a: Pre-flight sanity — both PRIM instances MUST be OPEN.
log "0a. Pre-flight: weryfikacja stanu PRIM (oba PRIM1+PRIM2 musza byc OPEN)... / Pre-flight: PRIM state check..."
PRIM_STATUS=$(srvctl status database -db PRIM -verbose 2>&1 || true)
echo "$PRIM_STATUS"
PRIM_OPEN_COUNT=$(echo "$PRIM_STATUS" | grep -c "Instance status: Open" || true)
if [ "$PRIM_OPEN_COUNT" -lt 2 ]; then
    log "BŁĄD: oczekuję 2 instancji PRIM w stanie 'Open', znaleziono: $PRIM_OPEN_COUNT"
    log "ERROR: expected 2 PRIM instances 'Open', found: $PRIM_OPEN_COUNT"
    log "Napraw przed kontynuacja: srvctl stop instance -db PRIM -instance PRIM2 -force"
    log "                          srvctl start instance -db PRIM -instance PRIM2 -startoption OPEN"
    log "                          ALTER PLUGGABLE DATABASE APPPDB OPEN INSTANCES=ALL"
    exit 1
fi
log "  OK — oba PRIM1 i PRIM2 sa OPEN / both PRIM instances OPEN"

# FIX-S28-44b: Defensive cleanup brokera na PRIM (idempotency dla re-runow).
# Greenfield: broker disabled, REMOVE i SET FALSE no-op.
# Re-run po wczesniejszej probie: REMOVE config → SET FALSE → potem mozna zmienic
# dg_broker_config_file (inaczej krok 5 dostaje ORA-16573).
# FIX-S28-44b: Idempotent broker reset on PRIM (greenfield no-op, re-run safe).
log "0b. Defensive reset brokera na PRIM (idempotent)... / Defensive broker reset on PRIM..."
TNS_DIR_PREFLIGHT="$HOME/tns_dgmgrl_preflight"
mkdir -p "$TNS_DIR_PREFLIGHT"
# Tymczasowy tnsnames bez wallet — uzyjemy bezposrednio sysdba
sqlplus -s / as sysdba <<'EOF' 2>&1 | grep -v -E '^$|connected|altered|disconnected' || true
WHENEVER SQLERROR CONTINUE;
ALTER SYSTEM SET DG_BROKER_START=FALSE SCOPE=BOTH SID='*';
EXIT;
EOF
sleep 5
log "  OK — broker zatrzymany na PRIM (jesli byl uruchomiony) / broker stopped on PRIM (if was running)"

log "1. Export i dystrybucja pliku hasel (Password File)... / 1. Export and distribution of Password File..."
# FIX-S28-25: usunięto `. oraenv` — PRIM1 nie ma wpisu w /etc/oratab (RAC CRS zarządza
# instancjami; /etc/oratab ma tylko +ASM1 i ewentualnie PRIM). Oraenv wywoływał dbhome PRIM1
# → zwracało /home/oracle jako ORACLE_HOME → oraenv exit 2 → set -e killował skrypt.
# ORACLE_HOME i PATH są już poprawnie ustawione z .bash_profile użytkownika oracle.
# FIX-S28-25: removed `. oraenv` — PRIM1 has no entry in /etc/oratab (RAC CRS manages
# instances; oraenv returned /home/oracle as ORACLE_HOME → exit 2 → set -e killed script).
# ORACLE_HOME and PATH are correctly set from oracle's .bash_profile.
export ORACLE_SID=PRIM1

mkdir -p /tmp/pwd
# FIX-S28-28: asmcmd pwcopy wykonuje operacje przez proces ASM (grid user); katalog /tmp/pwd
# nalezacy do oracle (755) blokuje zapis → ORA-27040 Permission denied.
# Fix: chmod 1777 /tmp/pwd (world-writable + sticky) → grid moze pisac; oracle czyta przez
# grupe oinstall (plik grid:oinstall 644). chmod 640 usunieto — oracle nie moze chmodowac
# plikow nalezacych do grid.
# FIX-S28-28: asmcmd pwcopy runs through ASM process (grid user); /tmp/pwd owned by oracle
# (755) blocks write → ORA-27040. Fix: chmod 1777 so grid can write; oracle reads via oinstall.
chmod 1777 /tmp/pwd
export ORACLE_SID=+ASM1
PWFILE=$(asmcmd pwget --dbuniquename PRIM)
asmcmd pwcopy "$PWFILE" /tmp/pwd/orapwPRIM -f
export ORACLE_SID=PRIM1

# Kopiowanie na STBY / Copying to STBY
log "Kopiowanie orapw do stby01... / Copying orapw to stby01..."
scp /tmp/pwd/orapwPRIM oracle@stby01:/u01/app/oracle/product/23.26/dbhome_1/dbs/orapwSTBY

log "2. Konfiguracja sieci Oracle (Listener & TNS) na STBY... / 2. Configuring Oracle network (Listener & TNS) on STBY..."
# FIX-S28-50: LISTENER (port 1521) na stby01 jako HAS resource (Oracle Restart).
# Domyślnie CRS_SWONLY install + roothas.pl NIE tworzy ora.LISTENER.lsnr → po reboot listener
# nie wstaje, ORA-16778 (broker redo transport error). Fix: listener.ora w GRID_HOME (grid),
# `srvctl add listener` rejestruje jako HAS resource z auto-start.
# tnsnames.ora pozostaje w DB_HOME (oracle) bo używany przez sqlplus i klienty oracle.
# FIX-S28-50: LISTENER on port 1521 as HAS resource — auto-start after reboot.
ssh grid@stby01 "mkdir -p /u01/app/23.26/grid/network/admin && cat >> /u01/app/23.26/grid/network/admin/listener.ora" <<'LORA'

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

# Add listener jako HAS resource (idempotentny — || true gdy już istnieje)
ssh grid@stby01 ". ~/.bash_profile && srvctl add listener -listener LISTENER -endpoints 'TCP:1521' 2>&1 || echo '  (LISTENER juz w HAS — pomijam add)'"
ssh grid@stby01 ". ~/.bash_profile && srvctl start listener -listener LISTENER 2>&1 || true"

# tnsnames.ora w DB_HOME (oracle, dla sqlplus i klientów)
ssh oracle@stby01 << 'EOF'
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
mkdir -p $ORACLE_HOME/network/admin

# TNSNAMES
# FIX-040: Oracle 23.26.1 z db_domain=lab.local rejestruje serwisy jako NAZWA.lab.local
# SERVICE_NAME bez domeny → ORA-12514. Wymagany suffix .lab.local.
# FIX-S28-31: SCAN listener nie widzi serwisu PRIM.lab.local (remote_listener nie ustawiony).
# Lokalne listenery na prim01/prim02 maja serwis — uzyj ADDRESS_LIST z obu node IPs.
# FIX-S28-38: LOAD_BALANCE=off + FAILOVER=on (NIE on) — RMAN Active Duplicate z RAC primary
# wymaga deterministycznego connecta do JEDNEJ instancji. AUX RPC back do TARGET przez
# load-balanced alias trafialo na rozne nody → ORA-01138 (instancje w roznym stanie podczas
# DBMS_BACKUP_RESTORE.RESTORESETPIECE). Pin do prim01, fallback na prim02 jesli prim01 down.
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

EOF
# UWAGA: LISTENER 1521 wystartowany juz przez `srvctl start listener` (HAS) powyzej.
# NIE robimy `lsnrctl start` z oracle — to zaczeloby drugi listener i kolizja portu.

log "3. Przygotowanie docelowych katalogow i start w NOMOUNT na STBY... / 3. Preparing target directories and starting in NOMOUNT on STBY..."
ssh oracle@stby01 << 'EOF'
export ORACLE_SID=STBY
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH

# FIX-S28-30: Oracle Restart automatycznie uruchamia baze STBY po instalacji GI/DB Software.
# Przed STARTUP NOMOUNT trzeba zatrzymac instancje — najpierw przez srvctl (jesli zarejestrowana),
# potem SHUTDOWN ABORT (gdy srvctl nie zna bazy lub juz jest down).
# FIX-S28-30: Oracle Restart auto-starts STBY after GI/DB software install.
# Must stop instance before STARTUP NOMOUNT — via srvctl first (if registered), then SHUTDOWN ABORT.
srvctl stop database -db STBY 2>/dev/null || true

# FIX-S28-37: cleanup pozostalosci po poprzednich nieudanych probach (datafiles, controlfile, SPFILE)
# inaczej RMAN DUPLICATE konflikt: ORA-19660 / ORA-19685 verification failures.
# FIX-S28-37: cleanup remnants from previous failed attempts (datafiles, controlfile, SPFILE)
# otherwise RMAN DUPLICATE conflict: ORA-19660 / ORA-19685 verification failures.
rm -f /u02/oradata/STBY/*.dbf /u02/oradata/STBY/*.ctl 2>/dev/null || true
rm -rf /u02/oradata/STBY/onlinelog/* 2>/dev/null || true
rm -f /u03/fra/STBY/*.ctl 2>/dev/null || true
rm -rf /u03/fra/STBY/onlinelog/* 2>/dev/null || true
rm -rf /u03/fra/STBY/STBY 2>/dev/null || true
rm -f $ORACLE_HOME/dbs/spfileSTBY.ora 2>/dev/null || true
# FIX-S28-42: usun stare pliki konfig brokera ze STBY (lokalne dr*STBY.dat).
# Pozostale po nieudanych ENABLE → ORA-16603 "member is part of another DG config"
# przy ADD DATABASE STBY na PRIM (mimo ze PRIM ma czysta konfig).
# FIX-S28-42: remove stale broker config files on STBY (local dr*STBY.dat).
# Leftover from failed ENABLE → ORA-16603 on ADD DATABASE STBY from PRIM.
rm -f $ORACLE_HOME/dbs/dr1STBY.dat $ORACLE_HOME/dbs/dr2STBY.dat 2>/dev/null || true

mkdir -p /u01/app/oracle/admin/STBY/adump
mkdir -p /u02/oradata/STBY/onlinelog
mkdir -p /u03/fra/STBY/onlinelog

# Minimalny init.ora (Broker nadpisze go SPFILE'm) / Minimal init.ora (Broker will overwrite it with SPFILE)
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
EOF

log "4. Konfiguracja sieci TNS na Primary (prim01, prim02)... / 4. Configuring TNS network on Primary (prim01, prim02)..."
# FIX-040: SERVICE_NAME musi miec suffix .lab.local (Oracle 23.26.1 z db_domain=lab.local)
# FIX-S28-31: ADDRESS_LIST z node IPs (nie SCAN) — SCAN listener nie widzi PRIM.lab.local
# bo remote_listener nie jest ustawiony. Lokalne listenery na prim01/prim02 maja serwis.
# FIX-S28-38: LOAD_BALANCE=off + FAILOVER=on — deterministyczny connect do prim01 dla RMAN.
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

# F-04: kopia tnsnames do lokalnego TNS_ADMIN-u walletowego, by /@PRIM rozwiazywal sie
#       bez modyfikowania globalnego sqlnet.ora w $ORACLE_HOME (mialoby wplyw na cluster).
# F-04: copy tnsnames.ora to wallet-local TNS_ADMIN so /@PRIM resolves without altering
#       the cluster-wide sqlnet.ora in $ORACLE_HOME.
cp -f "$ORACLE_HOME/network/admin/tnsnames.ora" "$TNS_DIR_LOCAL/tnsnames.ora"

log "4a. LISTENER_DGMGRL (port 1522) jako CRS/HAS resource — auto-start po reboot..."
# FIX-S28-49 (CRS-managed): LISTENER_DGMGRL na port 1522 dla broker StaticConnectIdentifier.
# Bez tego observerowie nie podlacza przez alias PRIM_ADMIN/STBY_ADMIN, switchover blokuje.
# Listener.ora w GRID_HOME (grid user) — zarzadzany przez CRS (RAC) lub HAS (Oracle Restart).
# srvctl add listener uruchamia listener auto po reboot bez recznych komend.
# FIX-S28-49 (CRS-managed): LISTENER_DGMGRL on port 1522 — auto-start after reboot via CRS/HAS.

# === RAC nodes (prim01/prim02) — listener.ora w GRID_HOME na kazdym nodzie ===
for NODE_HOST in prim01 prim02; do
    case "$NODE_HOST" in
        prim01) NODE_SID=PRIM1 ;;
        prim02) NODE_SID=PRIM2 ;;
    esac
    log "  Append LISTENER_DGMGRL do GRID_HOME listener.ora na ${NODE_HOST} (SID=${NODE_SID})..."
    ssh grid@${NODE_HOST} "cat >> /u01/app/23.26/grid/network/admin/listener.ora" <<LSNREOF

# FIX-S28-49: CRS-managed LISTENER_DGMGRL na port 1522 dla broker static connect.
LISTENER_DGMGRL =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = ${NODE_HOST}.lab.local)(PORT = 1522))
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

# srvctl add — RAC cluster-wide (jeden CRS resource ora.LISTENER_DGMGRL.lsnr na obu nodach).
# Idempotent: || true gdy juz istnieje (re-run skryptu).
ssh grid@prim01 ". ~/.bash_profile && srvctl add listener -listener LISTENER_DGMGRL -endpoints 'TCP:1522' 2>&1 || echo '  (LISTENER_DGMGRL juz w CRS — pomijam add)'"
ssh grid@prim01 ". ~/.bash_profile && srvctl start listener -listener LISTENER_DGMGRL 2>&1 || true"
ssh grid@prim01 ". ~/.bash_profile && srvctl status listener -listener LISTENER_DGMGRL"

# === stby01 (Oracle Restart, HAS) — listener.ora w GRID_HOME, srvctl add (HAS resource) ===
log "4b. LISTENER_DGMGRL na stby01 jako HAS resource..."
ssh grid@stby01 "mkdir -p /u01/app/23.26/grid/network/admin && cat >> /u01/app/23.26/grid/network/admin/listener.ora" <<'LSNREOF'

# FIX-S28-49: HAS-managed LISTENER_DGMGRL na port 1522.
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

ssh grid@stby01 ". ~/.bash_profile && srvctl add listener -listener LISTENER_DGMGRL -endpoints 'TCP:1522' 2>&1 || echo '  (LISTENER_DGMGRL juz w HAS — pomijam add)'"
ssh grid@stby01 ". ~/.bash_profile && srvctl start listener -listener LISTENER_DGMGRL 2>&1 || true"
ssh grid@stby01 ". ~/.bash_profile && srvctl status listener -listener LISTENER_DGMGRL"

# === CSSD AUTO_START na stby01 (FIX-S28-48 trwale) ===
log "4c. CSSD AUTO_START=always na stby01 (po boot wstaje sam)..."
# FIX-S28-48: bez AUTO_START=always CSSD jest OFFLINE po reboot stby01 → srvctl rzuca PRCR-1055.
# AUTO_START=always wymusza ONLINE niezaleznie od stanu przy poprzednim shutdown.
ssh root@stby01 "/u01/app/23.26/grid/bin/crsctl modify resource ora.cssd -attr 'AUTO_START=always' -init"
ssh root@stby01 "/u01/app/23.26/grid/bin/crsctl status resource ora.cssd -p -init | grep AUTO_START"

log "5. Włączenie Brokera na Głównej Bazie (Primary)... / 5. Enabling Broker on Primary Database..."
# FIX-S28-40: dg_broker_config_file1/2 MUSZĄ być w shared storage (ASM) dla RAC.
# Domyślnie Oracle ustawia je na lokalne $ORACLE_HOME/dbs/dr1<DB>.dat — w RAC PRIM1 zapisuje
# konfig brokera lokalnie, PRIM2 nie widzi → ORA-16532 ("broker configuration does not exist")
# w SHOW CONFIGURATION. Ustawiamy na +DATA / +RECO PRZED pierwszym DG_BROKER_START=TRUE,
# wtedy broker startując utworzy pliki bezpośrednio w ASM.
# FIX-S28-40: dg_broker_config_file1/2 MUST be in shared storage (ASM) for RAC. Default local
# $ORACLE_HOME/dbs/ paths cause PRIM2 to not see PRIM1's broker config → ORA-16532.
sqlplus -s / as sysdba << 'EOF'
ALTER SYSTEM SET dg_broker_config_file1='+DATA/PRIM/dr1PRIM.dat' SCOPE=BOTH SID='*';
ALTER SYSTEM SET dg_broker_config_file2='+RECO/PRIM/dr2PRIM.dat' SCOPE=BOTH SID='*';
ALTER SYSTEM SET DG_BROKER_START=TRUE SCOPE=BOTH SID='*';
EXIT;
EOF

# FIX-S28-43: Standby Redo Logs (SRL) na PRIM — wymagane gdy PRIM stanie sie standby po
# switchover. 6 SRL (3 per thread × 2 thready RAC), kazdy o rozmiarze ORL (200M default).
# Idempotentne — pomija jesli SRL juz istnieja.
# FIX-S28-43: SRL on PRIM — required when PRIM becomes standby after switchover.
sqlplus -s / as sysdba << 'EOF'
SET SERVEROUTPUT ON
DECLARE
  v_count NUMBER;
  v_size  NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM v$standby_log;
  IF v_count = 0 THEN
    SELECT bytes/1024/1024 INTO v_size FROM v$log WHERE rownum = 1;
    DBMS_OUTPUT.PUT_LINE('Tworzenie 6 SRL na PRIM (size=' || v_size || 'M, +DATA)...');
    EXECUTE IMMEDIATE 'ALTER DATABASE ADD STANDBY LOGFILE THREAD 1 GROUP 11 ''+DATA'' SIZE ' || v_size || 'M';
    EXECUTE IMMEDIATE 'ALTER DATABASE ADD STANDBY LOGFILE THREAD 1 GROUP 12 ''+DATA'' SIZE ' || v_size || 'M';
    EXECUTE IMMEDIATE 'ALTER DATABASE ADD STANDBY LOGFILE THREAD 1 GROUP 13 ''+DATA'' SIZE ' || v_size || 'M';
    EXECUTE IMMEDIATE 'ALTER DATABASE ADD STANDBY LOGFILE THREAD 2 GROUP 21 ''+DATA'' SIZE ' || v_size || 'M';
    EXECUTE IMMEDIATE 'ALTER DATABASE ADD STANDBY LOGFILE THREAD 2 GROUP 22 ''+DATA'' SIZE ' || v_size || 'M';
    EXECUTE IMMEDIATE 'ALTER DATABASE ADD STANDBY LOGFILE THREAD 2 GROUP 23 ''+DATA'' SIZE ' || v_size || 'M';
    DBMS_OUTPUT.PUT_LINE('OK — 6 SRL utworzonych');
  ELSE
    DBMS_OUTPUT.PUT_LINE('SKIP — ' || v_count || ' SRL juz istnieja na PRIM');
  END IF;
END;
/
EXIT;
EOF

log "6. Czekam na gotowość DG Broker na Primary... / 6. Waiting for DG Broker on Primary..."
# FIX-S28-35: ORA-16525 (broker not yet available) przy próbie ADD DATABASE tuż po
# DG_BROKER_START=TRUE. Broker startuje asynchronicznie i potrzebuje ~20-30s.
# CREATE CONFIGURATION + ADD DATABASE przeniesione do kroku 6c (po RMAN Duplicate),
# kiedy broker na pewno jest juz gotowy.
# FIX-S28-35: ORA-16525 when calling ADD DATABASE immediately after DG_BROKER_START=TRUE.
# Broker starts asynchronously. CREATE CONFIGURATION + ADD DATABASE moved to step 6c
# (after RMAN Duplicate) when broker is guaranteed to be ready.
sleep 30

log "6a. RMAN Active Duplicate — tworzenie Physical Standby (kilkanaście minut)... / 6a. RMAN Active Duplicate — creating Physical Standby (several minutes)..."
# FIX-043: RMAN Auxiliary laczy sie do STBY przez SID (nie SERVICE_NAME) bo STBY jest w NOMOUNT.
# W NOMOUNT mode db_domain nie jest aktywna → SERVICE_NAME=STBY.lab.local nie matchuje listenera.
# Uzyj SID=STBY (matchuje SID_NAME=STBY w static listener.ora na stby01) + UR=A.
# FIX-042: SET remote_listener='' w SPFILE (RAC primary ma scan-prim; SI standby bez SCAN).
# FIX-S28-36: SET use_large_pages='FALSE' — RMAN kopiuje SPFILE z RAC primary ktory moze miec
# use_large_pages=ONLY/TRUE. stby01 nie ma HugePages skonfigurowanych → ORA-27106 przy starcie.
# FIX-S28-37: Primary RAC uzywa OMF (db_create_file_dest='+DATA', db_recovery_file_dest='+RECO').
# Klon dziedziczy te ustawienia ze SPFILE. Na stby01 nie ma ASM → ORA-19660/ORA-19685 przy
# verify backupset. Nadpisz przez SET db_create_file_dest, db_recovery_file_dest, control_files.
# FIX-043: RMAN Auxiliary connects via SID (not SERVICE_NAME) because STBY is in NOMOUNT.
# NOMOUNT mode: db_domain not active → SERVICE_NAME=STBY.lab.local won't match static listener.
# Use SID=STBY (matches SID_NAME=STBY in static listener.ora on stby01) + UR=A.
# FIX-042: SET remote_listener='' in SPFILE (RAC primary has scan-prim; SI standby has no SCAN).
# FIX-S28-36: SET use_large_pages='FALSE' — RAC primary SPFILE may have use_large_pages=ONLY/TRUE.
# stby01 has no HugePages configured → ORA-27106 (system pages not available) on restart.
RMAN_AUX_CONN="(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=stby01.lab.local)(PORT=1521))(CONNECT_DATA=(SID=STBY)(UR=A)))"
TNS_ADMIN="$TNS_DIR_LOCAL" rman \
    target "/@PRIM" \
    auxiliary "sys/$LAB_PASS@\"$RMAN_AUX_CONN\"" << 'RMANEOF'
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
RMANEOF

log "6b. Post-RMAN parametry SPFILE na STBY i rejestracja serwisow... / 6b. Post-RMAN SPFILE params on STBY and service registration..."
# FIX-041: cluster_database_instances i instance_number — NIE moga byc w RMAN SET clause
# (RMAN-06581 w 26ai), ustawiane post-duplicate przez ALTER SYSTEM SCOPE=SPFILE.
# FIX-042: remote_listener juz wyzerowany przez SET w RMAN DUPLICATE (SET remote_listener='').
# FIX-041: cluster_database_instances and instance_number — cannot be in RMAN SET clause
# (RMAN-06581 in 26ai), set post-duplicate via ALTER SYSTEM SCOPE=SPFILE.
# FIX-042: remote_listener already reset by SET clause in RMAN DUPLICATE.
ssh oracle@stby01 << 'SFEOF'
export ORACLE_SID=STBY
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
sqlplus -s / as sysdba <<SQL
-- FIX-S28-41: cluster_database_instances pominiete w SI (cluster_database=FALSE)
-- → ORA-02065 "illegal option for ALTER SYSTEM". instance_number wystarczy dla SI.
WHENEVER SQLERROR CONTINUE;
ALTER SYSTEM SET cluster_database_instances=1 SCOPE=SPFILE;
WHENEVER SQLERROR EXIT FAILURE;
ALTER SYSTEM SET instance_number=1 SCOPE=SPFILE;
ALTER SYSTEM REGISTER;
EXIT;
SQL
SFEOF

log "6c. Tworzenie Standby Redo Logs (SRL) na STBY... / 6c. Creating Standby Redo Logs (SRL) on STBY..."
# FIX-S28-43: Real-time apply + FSFO wymagaja SRL. Bez SRL transport idzie tylko po archiwizacji
# → Apply Lag rosnie liniowo (= czas od ostatniego archived log na PRIM). FSFO odmawia ENABLE.
# 6 SRL = 3 per thread × 2 thready RAC PRIM (kazdy o rozmiarze ORL = 200M default DBCA).
# stby01 nie ma ASM — pliki w XFS /u02/oradata/STBY/onlinelog/.
# Idempotentne — pomija jesli SRL juz istnieja (re-runy).
# FIX-S28-43: Real-time apply + FSFO require SRL. Without SRL apply lag grows linearly.
# 6 SRL on STBY (XFS, since stby01 has no ASM).
ssh oracle@stby01 << 'SFEOF'
export ORACLE_SID=STBY
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
sqlplus -s / as sysdba <<SQL
SET SERVEROUTPUT ON
DECLARE
  v_count NUMBER;
  v_size  NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM v\$standby_log;
  IF v_count = 0 THEN
    SELECT bytes/1024/1024 INTO v_size FROM v\$log WHERE rownum = 1;
    DBMS_OUTPUT.PUT_LINE('Tworzenie 6 SRL na STBY (size=' || v_size || 'M, /u02/oradata/STBY/onlinelog/)...');
    EXECUTE IMMEDIATE 'ALTER SYSTEM SET standby_file_management=MANUAL SCOPE=BOTH';
    EXECUTE IMMEDIATE 'ALTER DATABASE ADD STANDBY LOGFILE THREAD 1 GROUP 11 ''/u02/oradata/STBY/onlinelog/srl_t1g11.log'' SIZE ' || v_size || 'M';
    EXECUTE IMMEDIATE 'ALTER DATABASE ADD STANDBY LOGFILE THREAD 1 GROUP 12 ''/u02/oradata/STBY/onlinelog/srl_t1g12.log'' SIZE ' || v_size || 'M';
    EXECUTE IMMEDIATE 'ALTER DATABASE ADD STANDBY LOGFILE THREAD 1 GROUP 13 ''/u02/oradata/STBY/onlinelog/srl_t1g13.log'' SIZE ' || v_size || 'M';
    EXECUTE IMMEDIATE 'ALTER DATABASE ADD STANDBY LOGFILE THREAD 2 GROUP 21 ''/u02/oradata/STBY/onlinelog/srl_t2g21.log'' SIZE ' || v_size || 'M';
    EXECUTE IMMEDIATE 'ALTER DATABASE ADD STANDBY LOGFILE THREAD 2 GROUP 22 ''/u02/oradata/STBY/onlinelog/srl_t2g22.log'' SIZE ' || v_size || 'M';
    EXECUTE IMMEDIATE 'ALTER DATABASE ADD STANDBY LOGFILE THREAD 2 GROUP 23 ''/u02/oradata/STBY/onlinelog/srl_t2g23.log'' SIZE ' || v_size || 'M';
    EXECUTE IMMEDIATE 'ALTER SYSTEM SET standby_file_management=AUTO SCOPE=BOTH';
    DBMS_OUTPUT.PUT_LINE('OK — 6 SRL utworzonych na STBY');
  ELSE
    DBMS_OUTPUT.PUT_LINE('SKIP — ' || v_count || ' SRL juz istnieja na STBY');
  END IF;
END;
/
EXIT;
SQL
SFEOF

log "6d. DGMGRL — konfiguracja brokera + ENABLE CONFIGURATION... / 6d. DGMGRL — broker config + ENABLE CONFIGURATION..."
# FIX-S28-35: CREATE CONFIGURATION + ADD DATABASE tutaj (po RMAN), nie w kroku 6.
# Broker jest juz gotowy po kilku minutach RMAN Duplicate — brak ORA-16525.
# FIX-S28-35: CREATE CONFIGURATION + ADD DATABASE here (after RMAN), not in step 6.
# Broker is ready after several minutes of RMAN Duplicate — no ORA-16525.
TNS_ADMIN="$TNS_DIR_LOCAL" dgmgrl /@PRIM << 'EOF'
CREATE CONFIGURATION fsfo_cfg AS PRIMARY DATABASE IS PRIM CONNECT IDENTIFIER IS "PRIM";
ADD DATABASE STBY AS CONNECT IDENTIFIER IS "STBY";
-- FIX-096: explicit StaticConnectIdentifier z PORT=1522 (DGMGRL listener).
-- Bez tego broker auto-derive bierze PORT z local_listener (1521) i przy switchover
-- rzuca ORA-12514 ("Service STBY_DGMGRL.lab.local is not registered ... port 1521").
-- For RAC: EDIT INSTANCE 'inst' ON DATABASE 'dbname'; for SI: EDIT DATABASE 'name'.
EDIT DATABASE 'stby' SET PROPERTY 'StaticConnectIdentifier'='(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=stby01.lab.local)(PORT=1522))(CONNECT_DATA=(SERVICE_NAME=STBY_DGMGRL.lab.local)(INSTANCE_NAME=STBY)(SERVER=DEDICATED)))';
EDIT INSTANCE 'PRIM1' ON DATABASE 'PRIM' SET PROPERTY 'StaticConnectIdentifier'='(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=prim01.lab.local)(PORT=1522))(CONNECT_DATA=(SERVICE_NAME=PRIM_DGMGRL.lab.local)(INSTANCE_NAME=PRIM1)(SERVER=DEDICATED)))';
EDIT INSTANCE 'PRIM2' ON DATABASE 'PRIM' SET PROPERTY 'StaticConnectIdentifier'='(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=prim02.lab.local)(PORT=1522))(CONNECT_DATA=(SERVICE_NAME=PRIM_DGMGRL.lab.local)(INSTANCE_NAME=PRIM2)(SERVER=DEDICATED)))';
ENABLE CONFIGURATION;
SHOW CONFIGURATION;
EXIT;
EOF

# FIX-S28-51: MaxAvailability + LogXptMode=SYNC dla Zero Data Loss (zgodnie z architektura
# 01_Architektura_i_Zalozenia.md i scenariuszem 4 z docs/09).
# Wymagane gdy FastStartFailoverLagLimit=0 (setup_observer.sh) — bez SYNC apply zawsze
# ma pewny lag, FSFO bedzie blokowany przy kazdej awarii.
# Aplikujemy PO ENABLE CONFIGURATION (broker musi byc enabled zeby zmienic Protection Mode).
# FIX-S28-51: MaxAvailability + SYNC for Zero Data Loss config alignment with FSFO LagLimit=0.
sleep 5
log "6e. MaxAvailability + LogXptMode=SYNC (Zero Data Loss alignment)... / 6e. MaxAvailability + SYNC..."
TNS_ADMIN="$TNS_DIR_LOCAL" dgmgrl /@PRIM <<'DGEOF'
EDIT DATABASE 'PRIM' SET PROPERTY 'LogXptMode'='SYNC';
EDIT DATABASE 'stby' SET PROPERTY 'LogXptMode'='SYNC';
EDIT CONFIGURATION SET PROTECTION MODE AS MAXAVAILABILITY;
SHOW CONFIGURATION;
EXIT;
DGEOF

log "7. Konfiguracja Active Data Guard na stby01 (READ ONLY WITH APPLY)... / 7. Active DG setup..."
# Active DG: STBY ma byc OPEN READ ONLY WITH APPLY (Real-Time Query). Wymaga licencji ADG.
# Procedura:
#  a) APPLY-OFF (broker) - musimy zatrzymac MRP zeby otworzyc PDB w RO i zapisac stan,
#  b) ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY + SAVE STATE,
#  c) srvctl modify database -startoption "READ ONLY" - po reboocie stby01 Oracle Restart
#     wystartuje DB od razu w READ ONLY (nie MOUNT),
#  d) APPLY-ON (broker) - apply wznowiony, baza w trybie Real-Time Query.
# Active DG: STBY in OPEN READ ONLY WITH APPLY (Real-Time Query). Requires ADG license.
TNS_ADMIN="$TNS_DIR_LOCAL" dgmgrl /@PRIM <<'DGEOF'
EDIT DATABASE 'stby' SET STATE='APPLY-OFF';
EXIT;
DGEOF

# Sprawdz czy stby01 zostalo otwarte; jesli MOUNTED, otworz RO + SAVE STATE PDBs.
# Skrypt SQL kierowany do STBY przez tnsalias.
TNS_ADMIN="$TNS_DIR_LOCAL" sqlplus -s /@STBY <<'SQLEOF'
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF
WHENEVER SQLERROR EXIT FAILURE

-- 1. Jesli baza jest tylko MOUNTED, otworz w READ ONLY.
DECLARE
    v_open_mode VARCHAR2(20);
BEGIN
    SELECT open_mode INTO v_open_mode FROM v$database;
    IF v_open_mode = 'MOUNTED' THEN
        EXECUTE IMMEDIATE 'ALTER DATABASE OPEN READ ONLY';
    END IF;
END;
/

-- 2. Otworz PDB w READ ONLY (Active DG wymaga otwartych PDB).
ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY;

-- 3. SAVE STATE - po STARTUP STBY otworzy PDB w READ ONLY automatycznie.
ALTER PLUGGABLE DATABASE ALL SAVE STATE;

EXIT;
SQLEOF

# S28-64: Modernizacja - rejestracja PDB jako CRS resource z policy AUTOMATIC + role PRIMARY.
# Bez tego: po kazdym switchover/failover trzeba recznie ALTER PLUGGABLE DATABASE OPEN READ WRITE
# + SAVE STATE na nowym primary (relikt starego SAVE STATE z poprzedniej roli).
# Z `srvctl modify pdb -policy AUTOMATIC -role PRIMARY`:
#   * Primary: CRS otwiera PDB w READ WRITE przy starcie (idempotent po role swap)
#   * Standby: CRS NIE rusza PDB - Active DG sam otwiera w READ ONLY
log "6f. Rejestracja PDB APPPDB w CRS jako AUTOMATIC + role PRIMARY (S28-64)..."
ssh oracle@prim01 ". ~/.bash_profile && srvctl modify pdb -db PRIM -pdb APPPDB -policy AUTOMATIC -role PRIMARY" || true
ssh oracle@stby01 ". ~/.bash_profile && srvctl modify pdb -db STBY -pdb APPPDB -policy AUTOMATIC -role PRIMARY" || true

# FIX-S28-46: Rejestracja STBY w HAS (Oracle Restart) na stby01.
# RMAN DUPLICATE NIE rejestruje bazy w HAS — po RMAN `srvctl status database -db STBY`
# zwraca PRCD-1120 / PRCR-1001 (resource ora.stby.db does not exist). Bez add:
#  - srvctl modify (krok 4 ponizej) dostaje PRCD-1120 i nie ustawia READ ONLY auto-start
#  - po reboot stby01 baza NIE wstanie automatycznie
#  - crsctl stat res -t pokazuje tylko ora.evmd + ora.ons (puste minimum HAS)
# Idempotent: || true dla re-runów (jeśli już zarejestrowana).
# FIX-S28-46: Register STBY in HAS (Oracle Restart) on stby01. Without this, srvctl modify
# fails with PRCD-1120 and STBY won't auto-start after stby01 reboot.
log "7a. Sprawdzenie i start CSSD na stby01 (wymagany przez srvctl)... / 7a. Ensuring CSSD on stby01..."
# FIX-S28-48: CRS_SWONLY install nie auto-startuje CSSD po boot. AUTO_START=always
# zostalo ustawione w kroku 4c, ale przy pierwszym deployu (greenfield) CSSD moze byc
# OFFLINE — sprawdzamy i uruchamiamy jesli trzeba (po pierwszym uruchomieniu i AUTO_START
# zaaplikowanym, kolejne reboots automatycznie wstaja CSSD).
# FIX-S28-48: CSSD must be ONLINE before srvctl add database. AUTO_START set in 4c handles
# subsequent reboots; this step covers first run.
ssh root@stby01 << 'SSHEOF'
GRID_HOME=/u01/app/23.26/grid
CSS_STATE=$($GRID_HOME/bin/crsctl status resource ora.cssd -init 2>&1 | grep -i 'STATE=' | head -1 || true)
if echo "$CSS_STATE" | grep -q "ONLINE"; then
    echo "  [OK] CSSD już ONLINE na stby01 / CSSD already ONLINE"
else
    echo "  CSSD OFFLINE — uruchamiam... / Starting CSSD..."
    $GRID_HOME/bin/crsctl start resource ora.cssd -init
    sleep 15
    $GRID_HOME/bin/crsctl check css
fi
SSHEOF

log "7b. Rejestracja STBY w HAS (Oracle Restart)... / 7b. Registering STBY in HAS..."
ssh oracle@stby01 << 'SRVEOF'
. ~/.bash_profile
srvctl add database -db STBY \
    -oraclehome /u01/app/oracle/product/23.26/dbhome_1 \
    -spfile /u01/app/oracle/product/23.26/dbhome_1/dbs/spfileSTBY.ora \
    -role PHYSICAL_STANDBY \
    -startoption MOUNT \
    -policy AUTOMATIC \
    -domain lab.local 2>&1 || echo "  (STBY juz zarejestrowany w HAS — pomijam add) / (STBY already registered — skipping add)"
srvctl config database -db STBY 2>&1 | head -20
SRVEOF

# 4. Oracle Restart auto-open RO po reboot stby01 (zamiast default MOUNT dla standby).
ssh oracle@stby01 ". ~/.bash_profile && srvctl modify database -db STBY -startoption 'READ ONLY' && srvctl config database -db STBY | grep -E 'Start|Stop|Role|Open mode'"

# FIX-S28-47: Handoff bazy do HAS. Po `srvctl add database` baza nadal chodzi spoza HAS
# (faktyczny proces uruchomiony przez RMAN/ALTER DATABASE OPEN). crsctl stat res pokazuje
# `ora.stby.db OFFLINE OFFLINE` mimo działającej instancji. Trzeba shutdown + srvctl start
# żeby HAS przejął kontrolę. Inaczej po pierwszym reboot stby01 baza nie wstanie auto.
# Sekwencja: APPLY-OFF (broker zatrzymuje MRP) → SHUTDOWN IMMEDIATE → srvctl start
# (HAS uruchamia w READ ONLY) → APPLY-ON (broker resume).
log "7c. Handoff STBY do HAS (shutdown + srvctl start)... / 7c. STBY handoff to HAS..."
TNS_ADMIN="$TNS_DIR_LOCAL" dgmgrl /@PRIM <<'DGEOF'
EDIT DATABASE 'stby' SET STATE='APPLY-OFF';
EXIT;
DGEOF
sleep 5  # broker propagacja stop apply

ssh oracle@stby01 << 'SFEOF'
. ~/.bash_profile
sqlplus -s / as sysdba <<SQL
SHUTDOWN IMMEDIATE;
EXIT;
SQL
srvctl start database -db STBY
SFEOF

sleep 10  # HAS startuje bazę w READ ONLY

# 5. Wznow apply - teraz baza pracuje w trybie Real-Time Query pod HAS.
TNS_ADMIN="$TNS_DIR_LOCAL" dgmgrl /@PRIM <<'DGEOF'
EDIT DATABASE 'stby' SET STATE='APPLY-ON';
SHOW DATABASE 'stby';
EXIT;
DGEOF

# Final sanity check: HAS musi pokazać ONLINE ONLINE.
ssh grid@stby01 ". ~/.bash_profile && crsctl stat res ora.stby.db -t"
# Oczekiwane: ora.stby.db ONLINE ONLINE stby01 Open Read Only,STABLE

log "=========================================================="
log "    Baza Standby utworzona przez DGMGRL. Konfiguracja DG  "
log "    SUCCESS. Active DG aktywne (READ ONLY WITH APPLY).    "
log "    Standby DB ready as Active Data Guard (RO + Apply).   "
log "=========================================================="
log ""
log "Sanity check / Sanity check:"
log "  ssh oracle@stby01 'sqlplus -s / as sysdba <<<\"SELECT open_mode FROM v\\\$database;\"'"
log "  -> Oczekiwane / Expected: READ ONLY WITH APPLY"
