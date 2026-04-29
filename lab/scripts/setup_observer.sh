#!/bin/bash
# ==============================================================================
# Tytul:        setup_observer.sh
# Opis:         Parametryzowany installer FSFO Observer dla Oracle 26ai (Master + Backupy).
#               Obsluguje role:
#                 - master  (infra01, obs_ext)  - instaluje Oracle Client + ENABLE FSFO
#                 - backup  (prim01,  obs_dc)   - reuse istniejacego DB Home (dgmgrl)
#                 - backup  (stby01,  obs_dr)   - reuse istniejacego DB Home (dgmgrl)
# Description [EN]: Parametrized FSFO Observer installer for Oracle 26ai.
#                   Supports master (obs_ext) and backup (obs_dc, obs_dr) roles.
#
# Autor:        KCB Kris
# Data:         2026-04-27
# Wersja:       3.0 (VMs2-install) - F-03 multi-Observer + F-04 wallet/secrets
#
# Wymagania [PL]:    - root, dla Master: pakiet Oracle Client 23.26.1 w /mnt/oracle_binaries
#                    - LAB_PASS dostepne (zmienna srodowiskowa lub /root/.lab_secrets)
# Requirements [EN]: - root; for master role: Oracle Client 23.26.1 zip in /mnt/oracle_binaries
#                    - LAB_PASS available (env or /root/.lab_secrets)
#
# Uzycie [PL]:
#   # Master Observer (infra01, default):
#   sudo bash /tmp/scripts/setup_observer.sh
#   # Backup Observer obs_dc (prim01):
#   OBSERVER_ROLE=backup OBSERVER_NAME=obs_dc OBSERVER_HOST=prim01.lab.local \
#     ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1 \
#     sudo -E bash /tmp/scripts/setup_observer.sh
#   # Backup Observer obs_dr (stby01):
#   OBSERVER_ROLE=backup OBSERVER_NAME=obs_dr OBSERVER_HOST=stby01.lab.local \
#     ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1 \
#     sudo -E bash /tmp/scripts/setup_observer.sh
# Usage [EN]: see above; export the env vars before calling.
# ==============================================================================

set -euo pipefail

# F-20: guard rooty.
if [ "$(id -u)" -ne 0 ]; then
    echo "BŁĄD: setup_observer.sh musi byc uruchomiony jako root. / ERROR: must run as root."
    exit 1
fi

# F-04: hasla z external secret file lub env.
if [ -r /root/.lab_secrets ]; then
    # shellcheck source=/dev/null
    source /root/.lab_secrets
fi
if [ -z "${LAB_PASS:-}" ]; then
    echo "BŁĄD: LAB_PASS nieustawiona. Stworz /root/.lab_secrets z 'export LAB_PASS=...' (chmod 600)."
    exit 1
fi

# Parametry konfiguracyjne (overridable przez env). / Configurable parameters (env-overridable).
OBSERVER_ROLE="${OBSERVER_ROLE:-master}"          # master | backup
OBSERVER_NAME="${OBSERVER_NAME:-obs_ext}"         # obs_ext / obs_dc / obs_dr
OBSERVER_HOST="${OBSERVER_HOST:-infra01.lab.local}"
WALLET_DIR="${WALLET_DIR:-/etc/oracle/wallet/${OBSERVER_NAME}}"
TNS_DIR="${TNS_DIR:-/etc/oracle/tns/${OBSERVER_NAME}}"
LOG_DIR="${LOG_DIR:-/var/log/oracle/${OBSERVER_NAME}}"
ORACLE_HOME="${ORACLE_HOME:-/u01/app/oracle/product/23.26/client_1}"
CLIENT_ZIP="${CLIENT_ZIP:-/mnt/oracle_binaries/V1054587-01-OracleDatabaseClient23.26.1.0.0forLinux_x86-64.zip}"
RSP_FILE="${RSP_FILE:-/tmp/response_files/client.rsp}"
SVC_UNIT="dgmgrl-observer-${OBSERVER_NAME}.service"

echo "=========================================================="
echo "  FSFO Observer setup - role=${OBSERVER_ROLE}, name=${OBSERVER_NAME}"
echo "  host=${OBSERVER_HOST}, oracle_home=${ORACLE_HOME}"
echo "=========================================================="

# 1. Uzytkownik oracle (idempotency - moze juz istniec na prim01/stby01 z kickstartu).
# 1. oracle user (idempotent - may already exist on prim01/stby01 from kickstart).
groupadd -g 54321 oinstall 2>/dev/null || true
groupadd -g 54322 dba 2>/dev/null || true
groupadd -g 54325 dgdba 2>/dev/null || true
useradd -u 54322 -g oinstall -G dba,dgdba -m -s /bin/bash oracle 2>/dev/null || true
echo "oracle:${LAB_PASS}" | chpasswd

# 2. Instalacja Oracle Client tylko dla Master (infra01); Backup uzywa istniejacego DB Home.
# 2. Oracle Client install only for Master (infra01); Backup reuses existing DB Home.
if [ "$OBSERVER_ROLE" = "master" ]; then
    if [ ! -d "$ORACLE_HOME/bin" ] || [ ! -x "$ORACLE_HOME/bin/dgmgrl" ]; then
        echo "[Master] Brak Oracle Client w ${ORACLE_HOME}; instaluje silent... / [Master] Installing Client..."
        mkdir -p "$ORACLE_HOME"
        mkdir -p /u01/app/oraInventory
        chown -R oracle:oinstall /u01/app
        chmod -R 775 /u01/app

        if [ ! -f "$CLIENT_ZIP" ]; then
            echo "BŁĄD: brak pliku Client zip ${CLIENT_ZIP}. / ERROR: missing Client zip."
            exit 1
        fi
        if [ ! -f "$RSP_FILE" ]; then
            echo "BŁĄD: brak ${RSP_FILE}. / ERROR: missing client.rsp."
            exit 1
        fi
        su - oracle -c "mkdir -p /tmp/client && cd /tmp/client && unzip -q '$CLIENT_ZIP'"
        cp "$RSP_FILE" /tmp/client.rsp
        chown oracle:oinstall /tmp/client.rsp

        # F-01: jawne sprawdzanie kodu wyjscia runInstaller.
        set +e
        su - oracle -c "cd /tmp/client/client && ./runInstaller -silent -responseFile /tmp/client.rsp -ignorePrereqFailure"
        RIC=$?
        set -e
        if [ $RIC -ne 0 ]; then
            echo "[FATAL] runInstaller (Client) zwrocil kod $RIC. Sprawdz logi w /u01/app/oraInventory/logs/."
            exit "$RIC"
        fi
        /u01/app/oraInventory/orainstRoot.sh
        rm -rf /tmp/client
    else
        echo "[Master] Oracle Client juz zainstalowany w ${ORACLE_HOME} - pomijam. / [Master] Client already present, skipping."
    fi

    # bash_profile dla oracle (tylko Master; na prim/stby kickstart juz to ma).
    if ! grep -q "TNS_ADMIN=$TNS_DIR" /home/oracle/.bash_profile 2>/dev/null; then
        cat >> /home/oracle/.bash_profile <<EOF

# Observer ${OBSERVER_NAME} environment
export ORACLE_HOME=${ORACLE_HOME}
export PATH=\$ORACLE_HOME/bin:\$PATH
export LD_LIBRARY_PATH=\$ORACLE_HOME/lib:/usr/lib
export TNS_ADMIN=${TNS_DIR}
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
export NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS'
umask 022
EOF
    fi
fi

# 3. Katalogi TNS / Wallet / Log.
mkdir -p "$TNS_DIR" "$WALLET_DIR" "$LOG_DIR"
chown -R oracle:oinstall "$TNS_DIR" "$WALLET_DIR" "$LOG_DIR"
chmod 755 "$TNS_DIR" "$LOG_DIR"
chmod 700 "$WALLET_DIR"

# 4. tnsnames.ora i sqlnet.ora (FIX-072: AUTHENTICATION_SERVICES=NONE).
# FIX-040 / S28-29: SERVICE_NAME=PRIM_DGMGRL.lab.local (z domain) — db_domain=lab.local
# rejestruje serwisy z suffixem; bez tego ORA-12514 przy `dgmgrl /@PRIM_ADMIN`.
# FIX-S28-38: LOAD_BALANCE=off + FAILOVER=on dla deterministycznego connecta do RAC.
cat > "$TNS_DIR/tnsnames.ora" <<'TNSEOF'
# _ADMIN aliasy: 1522 (LISTENER_DGMGRL) + SERVICE_NAME=*_DGMGRL — broker connect.
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

# S28-56: aliasy PRIM/STBY = DGConnectIdentifier observera (bez tego ORA-12154 w log
# observera "Cannot find alias PRIM"). Port 1521 + service_name = db_unique_name.lab.local.
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
TNSEOF

cat > "$TNS_DIR/sqlnet.ora" <<SQLNETEOF
WALLET_LOCATION = (SOURCE = (METHOD = FILE) (METHOD_DATA = (DIRECTORY = ${WALLET_DIR})))
SQLNET.WALLET_OVERRIDE = TRUE
# FIX-072 dla 26ai: NONE blokuje konflikt z NTS i pozwala wallet auto-login.
SQLNET.AUTHENTICATION_SERVICES = (NONE)
SQLNET.EXPIRE_TIME = 1
SQLNETEOF

chown -R oracle:oinstall "$TNS_DIR"

# 5. Wallet auto-login.
# S28-53: mkstore w 26ai NIE akceptuje `-p <pwd>` na -create / -createCredential —
# pwd musi isc przez STDIN. Wzorzec VMs/FIX-071: build temp script jako oracle, mkstore
# czyta haslo z heredoc. -create pyta 2x (enter+confirm), -createCredential 1x (wallet pwd).
echo "Tworzenie/odtwarzanie wallet auto-login w ${WALLET_DIR}... / Creating wallet auto-login..."
WALLET_SCRIPT=$(mktemp /tmp/wallet_setup.XXXXXX.sh)
chown oracle:oinstall "$WALLET_SCRIPT"
chmod 700 "$WALLET_SCRIPT"
trap "rm -f '$WALLET_SCRIPT'" EXIT

cat > "$WALLET_SCRIPT" <<WALLETSCRIPT
#!/bin/bash
export ORACLE_HOME="${ORACLE_HOME}"
export PATH="\$ORACLE_HOME/bin:\$PATH"
export LD_LIBRARY_PATH="\$ORACLE_HOME/lib:/usr/lib"
export TNS_ADMIN="${TNS_DIR}"
WP='${LAB_PASS}'
WL='${WALLET_DIR}'

# Helper: idempotent credential setup — list -> create OR modify
ensure_cred() {
    local ALIAS=\$1
    # S28-57-bis: -wq word-boundary; bez tego grep "PRIM" lapal "PRIM_ADMIN" → modify nieistniejacego.
    if printf '%s\n' "\$WP" | mkstore -wrl "\$WL" -listCredential -nologo 2>/dev/null | grep -qw "\$ALIAS"; then
        printf '%s\n' "\$WP" | mkstore -wrl "\$WL" -modifyCredential "\$ALIAS" sys "\$WP" -nologo
    else
        printf '%s\n' "\$WP" | mkstore -wrl "\$WL" -createCredential "\$ALIAS" sys "\$WP" -nologo
    fi
}

# 1. Create wallet (idempotent: skip jesli cwallet.sso istnieje)
if [ ! -f "\$WL/cwallet.sso" ]; then
    printf '%s\n%s\n' "\$WP" "\$WP" | mkstore -wrl "\$WL" -create -nologo
fi

# 2-5. Credentials (idempotent): _ADMIN dla broker (1522), bare nazwy dla observera (1521)
# S28-57: bez PRIM/STBY w wallet observer dostawal DGM-16979 "Authentication failed"
# po log into PRIM (bo wallet override = TRUE → szuka credential dla aliasu).
ensure_cred PRIM_ADMIN
ensure_cred STBY_ADMIN
ensure_cred PRIM
ensure_cred STBY
WALLETSCRIPT
chown oracle:oinstall "$WALLET_SCRIPT"
chmod 700 "$WALLET_SCRIPT"
su - oracle -c "bash $WALLET_SCRIPT"
rm -f "$WALLET_SCRIPT"
trap - EXIT

# 6. Systemd unit (FIX-074, FIX-075).
echo "Konfiguracja systemd ${SVC_UNIT}... / Configuring systemd unit..."
cat > "/etc/systemd/system/${SVC_UNIT}" <<UNITEOF
[Unit]
Description=Oracle Data Guard Observer ${OBSERVER_NAME} (FSFO ${OBSERVER_ROLE})
After=network-online.target chronyd.service

[Service]
Type=simple
User=oracle
Group=oinstall
Environment="ORACLE_HOME=${ORACLE_HOME}"
Environment="TNS_ADMIN=${TNS_DIR}"
Environment="LD_LIBRARY_PATH=${ORACLE_HOME}/lib"
Environment="NLS_LANG=AMERICAN_AMERICA.AL32UTF8"
WorkingDirectory=${LOG_DIR}

# FIX-074/075: brak '-logfile' i 'IN BACKGROUND' - composite syntax 26ai.
# S28-54: ExecStart przez wrapper /usr/local/bin/start-observer-${OBSERVER_NAME}.sh -
# embedded single quotes w 'FILE IS ...' lamia parser systemd (status=203/EXEC). Wrapper
# bash -c eliminuje problem i zapewnia pelne env (ORACLE_HOME, LD_LIBRARY_PATH, TNS_ADMIN).
ExecStart=/usr/local/bin/start-observer-${OBSERVER_NAME}.sh
ExecStop=/usr/local/bin/stop-observer-${OBSERVER_NAME}.sh

Restart=on-failure
RestartSec=10s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNITEOF

# S28-54: wrapper scripts dla ExecStart/ExecStop (omijaja parser systemd na embedded quotes).
cat > "/usr/local/bin/start-observer-${OBSERVER_NAME}.sh" <<STARTEOF
#!/bin/bash
export ORACLE_HOME="${ORACLE_HOME}"
export PATH="\$ORACLE_HOME/bin:\$PATH"
export LD_LIBRARY_PATH="\$ORACLE_HOME/lib"
export TNS_ADMIN="${TNS_DIR}"
export NLS_LANG="AMERICAN_AMERICA.AL32UTF8"
exec "\$ORACLE_HOME/bin/dgmgrl" -echo /@PRIM_ADMIN "START OBSERVER ${OBSERVER_NAME} FILE IS '${LOG_DIR}/${OBSERVER_NAME}.dat' LOGFILE IS '${LOG_DIR}/${OBSERVER_NAME}.log'"
STARTEOF

cat > "/usr/local/bin/stop-observer-${OBSERVER_NAME}.sh" <<STOPEOF
#!/bin/bash
export ORACLE_HOME="${ORACLE_HOME}"
export PATH="\$ORACLE_HOME/bin:\$PATH"
export LD_LIBRARY_PATH="\$ORACLE_HOME/lib"
export TNS_ADMIN="${TNS_DIR}"
exec "\$ORACLE_HOME/bin/dgmgrl" /@PRIM_ADMIN "STOP OBSERVER ${OBSERVER_NAME}"
STOPEOF

chmod 755 "/usr/local/bin/start-observer-${OBSERVER_NAME}.sh" "/usr/local/bin/stop-observer-${OBSERVER_NAME}.sh"

systemctl daemon-reload

# 7. Rejestracja w brokerze (Backup) lub aktywacja FSFO (Master).
if [ "$OBSERVER_ROLE" = "master" ]; then
    echo "[Master] Start observera + ENABLE FAST_START FAILOVER... / [Master] Start observer + enable FSFO..."
    systemctl enable --now "${SVC_UNIT}"
    sleep 15

    PASS_VAR="$LAB_PASS" ORACLE_HOME_VAR="$ORACLE_HOME" TNS_DIR_VAR="$TNS_DIR" \
    su -p oracle <<'FSFOEOF'
export ORACLE_HOME="$ORACLE_HOME_VAR"
export PATH="$ORACLE_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$ORACLE_HOME/lib:/usr/lib"
export TNS_ADMIN="$TNS_DIR_VAR"
dgmgrl /@PRIM_ADMIN <<'DGMGRL'
EDIT CONFIGURATION SET PROPERTY FastStartFailoverThreshold=30;
EDIT CONFIGURATION SET PROPERTY FastStartFailoverLagLimit=0;
EDIT CONFIGURATION SET PROPERTY FastStartFailoverAutoReinstate=TRUE;
EDIT CONFIGURATION SET PROPERTY ObserverOverride=TRUE;
ENABLE FAST_START FAILOVER;
EXIT;
DGMGRL
FSFOEOF
else
    # S28-59: w 26ai NIE ma `ADD OBSERVER` (legacy 19c) — broker auto-rejestruje
    # observera przy `START OBSERVER` (wywolywane przez wrapper przy systemctl start).
    # Master juz Active → broker przypisze ${OBSERVER_NAME} jako Backup.
    echo "[Backup] Start observera ${OBSERVER_NAME} - broker auto-rejestruje jako Backup..."
    systemctl enable --now "${SVC_UNIT}"
    sleep 10
fi

echo "=========================================================="
echo "  Observer ${OBSERVER_NAME} skonfigurowany (role=${OBSERVER_ROLE})."
echo "  Status: systemctl status ${SVC_UNIT}"
echo "  Logi:   ${LOG_DIR}/${OBSERVER_NAME}.log"
echo "  Weryfikacja: dgmgrl /@PRIM_ADMIN \"SHOW OBSERVERS;\""
echo "=========================================================="
