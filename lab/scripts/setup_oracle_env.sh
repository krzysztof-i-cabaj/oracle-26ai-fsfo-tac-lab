#!/bin/bash
# ==============================================================================
# Tytul:        setup_oracle_env.sh
# Opis:         Konfiguruje .bash_profile dla uzytkownikow grid i oracle
#               na wszystkich wezlach Oracle (prim01, prim02, stby01).
#               Naprawia rowniez wlasciwosc /etc/oraInst.loc (root:root).
#               Idempotentny — bezpieczne do wielokrotnego uruchomienia.
# Description [EN]: Configures .bash_profile for grid and oracle users
#               on all Oracle nodes (prim01, prim02, stby01).
#               Also fixes /etc/oraInst.loc group ownership (root:root).
#               Idempotent — safe to run multiple times.
#
# Autor:        KCB Kris
# Data:         2026-04-28
# Wersja:       1.2 (FIX-S28-41: ORACLE_SID per-wezel dla oracle — PRIM1/PRIM2/STBY)
#
# Wymagania [PL]:    - root@prim01
#                    - /root/.lab_secrets z LAB_PASS (tworzony przez ssh_setup.sh)
#                    - oracle-database-preinstall-23ai zainstalowany na wezlach
#                    - Uzytkownicy grid i oracle musza istniec na wezlach
# Requirements [EN]: - root@prim01
#                    - /root/.lab_secrets with LAB_PASS (created by ssh_setup.sh)
#                    - oracle-database-preinstall-23ai installed on all nodes
#                    - Users grid and oracle must exist on nodes
#
# Uzycie [PL]:       sudo bash /tmp/scripts/setup_oracle_env.sh
# Usage [EN]:        sudo bash /tmp/scripts/setup_oracle_env.sh
# ==============================================================================

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "BŁĄD: skrypt musi być uruchomiony jako root. / ERROR: must run as root."
    exit 1
fi

# Haslo z lab_secrets (jak w ssh_setup.sh) / Password from lab_secrets (as in ssh_setup.sh)
if [ -r /root/.lab_secrets ]; then
    # shellcheck source=/dev/null
    source /root/.lab_secrets
fi
if [ -z "${LAB_PASS:-}" ]; then
    echo "BŁĄD: LAB_PASS nieustawiony. Utwórz /root/.lab_secrets z: export LAB_PASS='haslo'"
    exit 1
fi

ALL_ORACLE_NODES="prim01 prim02 stby01"
REMOTE_NODES="prim02 stby01"
LOCAL_HOST=$(hostname -s)

GRID_HOME="/u01/app/23.26/grid"
DB_HOME="/u01/app/oracle/product/23.26/dbhome_1"

# --------------------------------------------------------------------------
# 0. Root SSH key — generuj jesli brak, kopiuj na wezly zdalne przez sshpass.
#    Root SSH key — generate if missing, copy to remote nodes via sshpass.
# --------------------------------------------------------------------------
echo ""
echo "=== 0/3  Root SSH key setup ==="
if [ ! -f /root/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -N '' -f /root/.ssh/id_rsa -q
    echo "  [OK]   Root SSH key generated"
fi

dnf install -y sshpass >/dev/null 2>&1 || true

for NODE in ${REMOTE_NODES}; do
    sshpass -p "${LAB_PASS}" ssh-copy-id \
        -o StrictHostKeyChecking=no \
        -i /root/.ssh/id_rsa.pub \
        root@${NODE} 2>/dev/null \
        && echo "  [OK]   root key copied to ${NODE}" \
        || echo "  [WARN] ssh-copy-id to ${NODE} — może już istnieje?"
done

# --------------------------------------------------------------------------
# node_bash NODE — przekazuje stdin do bash lokalnie lub przez SSH.
# node_bash NODE — pipes stdin to bash locally or via SSH root.
# --------------------------------------------------------------------------
node_bash() {
    local NODE=$1
    if [ "${NODE}" = "${LOCAL_HOST}" ]; then
        bash -s
    else
        ssh root@${NODE} bash -s
    fi
}

# --------------------------------------------------------------------------
# setup_profile NODE USER ORACLE_BASE ORACLE_HOME [ORACLE_SID]
# Idempotentne — pomija jesli ORACLE_HOME juz jest w .bash_profile.
# ORACLE_SID jest opcjonalne — uzyj dla grid (rozni sie per-wezel).
# --------------------------------------------------------------------------
setup_profile() {
    local NODE=$1
    local USER=$2
    local OBASE=$3
    local OHOME=$4
    local OSID=${5:-}

    node_bash "${NODE}" <<EOF
if grep -q 'ORACLE_HOME' /home/${USER}/.bash_profile 2>/dev/null; then
    echo "  [SKIP] ${USER}@${NODE} — ORACLE_HOME already in profile"
else
    cat >> /home/${USER}/.bash_profile <<'PROFILE'

export ORACLE_BASE=${OBASE}
export ORACLE_HOME=${OHOME}
export PATH=\$ORACLE_HOME/bin:\$PATH
export TNS_ADMIN=\$ORACLE_HOME/network/admin
PROFILE
    echo "  [OK]   ${USER}@${NODE} — .bash_profile updated"
fi

if [ -n "${OSID}" ]; then
    if grep -q 'ORACLE_SID' /home/${USER}/.bash_profile 2>/dev/null; then
        echo "  [SKIP] ${USER}@${NODE} — ORACLE_SID already in profile"
    else
        echo "export ORACLE_SID=${OSID}" >> /home/${USER}/.bash_profile
        echo "  [OK]   ${USER}@${NODE} — ORACLE_SID=${OSID} added"
    fi
fi
EOF
}

# --------------------------------------------------------------------------
# 1. Naprawa /etc/oraInst.loc — CVU PRVG-2032 oczekuje group=root(0)
# --------------------------------------------------------------------------
echo ""
echo "=== 1/3  /etc/oraInst.loc — chown root:root ==="
for NODE in ${ALL_ORACLE_NODES}; do
    node_bash "${NODE}" <<EOF
if [ -f /etc/oraInst.loc ]; then
    chown root:root /etc/oraInst.loc
    echo "  [OK]   fixed on ${NODE}"
else
    echo "  [SKIP] /etc/oraInst.loc not found on ${NODE}"
fi
EOF
done

# --------------------------------------------------------------------------
# 2. Profile uzytkownika grid
#    ORACLE_SID rozni sie per-wezel: RAC node1=+ASM1, node2=+ASM2, standalone=+ASM
# --------------------------------------------------------------------------
echo ""
echo "=== 2/3  .bash_profile — grid (GRID_HOME=${GRID_HOME}) ==="
setup_profile "prim01" "grid" "/u01/app/grid" "${GRID_HOME}" "+ASM1"
setup_profile "prim02" "grid" "/u01/app/grid" "${GRID_HOME}" "+ASM2"
setup_profile "stby01" "grid" "/u01/app/grid" "${GRID_HOME}" "+ASM"

# --------------------------------------------------------------------------
# 3. Profile uzytkownika oracle
#    ORACLE_SID per-wezel (FIX-S28-41): RAC node1=PRIM1, node2=PRIM2, standby=STBY.
#    Bez tego sqlplus / as sysdba zwraca ORA-12162 ("net service name incorrectly
#    specified") bo bez ORACLE_SID Oracle szuka aliasu sieciowego "" w tnsnames.
# --------------------------------------------------------------------------
echo ""
echo "=== 3/3  .bash_profile — oracle (DB_HOME=${DB_HOME}) ==="
setup_profile "prim01" "oracle" "/u01/app/oracle" "${DB_HOME}" "PRIM1"
setup_profile "prim02" "oracle" "/u01/app/oracle" "${DB_HOME}" "PRIM2"
setup_profile "stby01" "oracle" "/u01/app/oracle" "${DB_HOME}" "STBY"

echo ""
echo "================================================================"
echo "  Gotowe. Przeloguj uzytkownikow grid/oracle, aby wczytac env."
echo "  Done. Re-login as grid/oracle to apply the new profile."
echo "================================================================"
