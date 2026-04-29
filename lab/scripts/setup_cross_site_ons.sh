#!/bin/bash
# Skrypt: setup_cross_site_ons.sh | Script: setup_cross_site_ons.sh
# Cel: Konfiguracja ONS (Oracle Notification Service) pomiędzy RAC a Standby / Goal: Configure ONS (Oracle Notification Service) between RAC and Standby
#      dla powiadomień FAN (Fast Application Notification) / for FAN (Fast Application Notification) events
# Uruchamiac na: prim01 jako root / Run on: prim01 as root
# (S28-62: skrypt uzywa `su - grid -c srvctl ...` lokalnie i `ssh root@stby01` zdalnie -
# wymaga zatem root SSH equivalency root@prim01 -> root@stby01).

set -euo pipefail

echo "=========================================================="
echo "    Konfiguracja Cross-Site ONS (FAN events)              "
echo "    Cross-Site ONS Configuration (FAN events)             "
echo "=========================================================="

echo "1. Rejestracja zdalnego portu ONS w RAC (prim01)... / 1. Registering remote ONS port in RAC (prim01)..."
# S28-62: srvctl wymaga grid env (root nie ma w PATH). Wrapper przez su - grid.
# W 26ai usunieto flage -clusterid. Przekazujemy wylacznie -remoteservers.
# PRKO-2396 jesli juz ustawione - benign (idempotent re-run).
su - grid -c "srvctl modify ons -remoteservers stby01.lab.local:6200" 2>&1 | grep -vE "PRKO-2396" || true
su - grid -c "srvctl config ons" | grep -E "ONS exists|ONS is enabled" || true

echo "2. Zdalna rekonfiguracja ONS na Standby (stby01)... / 2. Remote ONS reconfiguration on Standby (stby01)..."
# ONS na SI Restart dziala z opmn/conf/ons.config (NIE jest CRS-resource jak w GI Cluster).
# S28-62: SSH jako root (klucz wrzucony) zamiast oracle+sudo (oracle nie ma NOPASSWD sudo).
# F-13/FIX-083: systemd unit z wrapperem (S28-54 pattern) zeby ONS startowal po reboocie.
ssh root@stby01 'bash -s' <<'EOF'
set -euo pipefail

# S28-62: ons.config bez 'loglevel' i 'useocr' - w 26ai te klucze sa unknown (warning w onsctl ping).
mkdir -p /u01/app/oracle/product/23.26/dbhome_1/opmn/conf
cat > /u01/app/oracle/product/23.26/dbhome_1/opmn/conf/ons.config <<ONS
usesharedinstall=true
localport=6100
remoteport=6200
nodes=stby01.lab.local:6200,prim01.lab.local:6200,prim02.lab.local:6200
ONS

chown oracle:oinstall /u01/app/oracle/product/23.26/dbhome_1/opmn/conf/ons.config
chmod 640 /u01/app/oracle/product/23.26/dbhome_1/opmn/conf/ons.config

echo "3a. Wrapper scripts dla ExecStart/ExecStop (S28-54 pattern - status=203/EXEC fix)..."
# S28-62: bez wrappera systemd dostawal status=203/EXEC bo onsctl wymaga LD_LIBRARY_PATH+PATH,
# nie tylko ORACLE_HOME (Environment= w unicie nie wystarczy).
cat > /usr/local/bin/start-ons.sh <<'STARTEOF'
#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:/usr/lib
exec $ORACLE_HOME/bin/onsctl start
STARTEOF

cat > /usr/local/bin/stop-ons.sh <<'STOPEOF'
#!/bin/bash
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:/usr/lib
exec $ORACLE_HOME/bin/onsctl stop
STOPEOF

chmod 755 /usr/local/bin/start-ons.sh /usr/local/bin/stop-ons.sh

echo "3b. Tworze systemd unit oracle-ons.service... / 3b. systemd unit..."
cat > /etc/systemd/system/oracle-ons.service <<'UNITEOF'
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
UNITEOF

systemctl daemon-reload
systemctl reset-failed oracle-ons.service 2>/dev/null || true
systemctl enable --now oracle-ons.service
sleep 3

echo "3c. Sanity-check..."
systemctl is-active oracle-ons.service
su - oracle -c 'export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1; export LD_LIBRARY_PATH=$ORACLE_HOME/lib; $ORACLE_HOME/bin/onsctl ping' || true
EOF

echo "Gotowe. Konfiguracja FAN miedzy PRIM a STBY aktywna i persystentna. / Done. FAN persistent across reboots."
