#!/bin/bash
# Skrypt do generowania i dystrybucji kluczy SSH pomiędzy węzłami klastra / Script for generating and distributing SSH keys between cluster nodes
# i maszyną Standby. Wymaga podania hasła podczas kopiowania, chyba że zostanie użyte sshpass. / and Standby machine. Requires password during copy unless sshpass is used.
# Uruchamiać jako root na prim01. / Run as root on prim01.

set -euo pipefail

# F-20: guard rooty - skrypt wymaga uprawnien root. / F-20: root guard - script requires root.
if [ "$(id -u)" -ne 0 ]; then
    echo "BŁĄD: ssh_setup.sh musi byc uruchomiony jako root (uid=0). / ERROR: ssh_setup.sh must run as root (uid=0)."
    echo "Uzyj / Use: sudo bash $0"
    exit 1
fi

# F-04: Haslo z external secret file. Fallback na zmienna srodowiskowa, inaczej blad. / F-04: Password from external secret file, env fallback, else fail.
if [ -r /root/.lab_secrets ]; then
    # shellcheck source=/dev/null
    source /root/.lab_secrets
fi
if [ -z "${LAB_PASS:-}" ]; then
    echo "BŁĄD: zmienna LAB_PASS nieustawiona. / ERROR: LAB_PASS not set."
    echo "Stworz plik /root/.lab_secrets (chmod 600) z linia:  export LAB_PASS='haslo'"
    echo "Lub uruchom: LAB_PASS='haslo' sudo -E bash $0"
    exit 1
fi
export LAB_PASS

# Lista węzłów dla grid (Full Mesh wymagany do instalacji klastra) / List of nodes for grid (Full Mesh required for cluster installation)
GRID_NODES="prim01 prim02"
# Lista węzłów dla oracle (Wymagane m.in. do RMAN Active Duplicate na Standby) / List of nodes for oracle (Required e.g. for RMAN Active Duplicate on Standby)
ORACLE_NODES="prim01 prim02 stby01 infra01"

echo "=========================================================="
echo "    Konfiguracja SSH User-Equivalency (Pełna Siatka)      "
echo "    SSH User-Equivalency Configuration (Full Mesh)        "
echo "=========================================================="

# Instalacja sshpass lokalnie / Install sshpass locally
dnf install -y sshpass >/dev/null 2>&1 || true

# Instalacja sshpass na wszystkich węzłach (wymagana do uruchamiania ssh-copy-id zdalnie)
# Install sshpass on all nodes (required for running ssh-copy-id remotely)
ALL_NODES=$(echo "$GRID_NODES $ORACLE_NODES" | tr ' ' '\n' | sort -u)
for _NODE in $ALL_NODES; do
    echo "Instalacja sshpass na $_NODE... / Installing sshpass on $_NODE..."
    sshpass -p "$LAB_PASS" ssh -o StrictHostKeyChecking=no root@$_NODE \
        "dnf install -y sshpass" >/dev/null 2>&1 \
        && echo "   [OK] $_NODE" \
        || echo "   [WARN] sshpass install na $_NODE nie powiodło się (może już jest?)"
done

# Funkcja konfigurująca pełną siatkę połączeń (Full Mesh) dla danego użytkownika / Function configuring full connection mesh (Full Mesh) for a given user
setup_full_mesh() {
    local USER=$1
    local NODES=$2
    
    echo "--- Konfiguracja siatki (Full Mesh) dla użytkownika: $USER --- / --- Configuring mesh (Full Mesh) for user: $USER ---"
    
    # Krok 1: Generowanie kluczy na kazdym wezle (jesli nie istnieja) / Step 1: Generating keys on each node (if they do not exist)
    for SOURCE_NODE in $NODES; do
        echo "Generowanie kluczy na węźle: $SOURCE_NODE dla usera $USER... / Generating keys on node: $SOURCE_NODE for user $USER..."
        sshpass -p "$LAB_PASS" ssh -o StrictHostKeyChecking=no root@$SOURCE_NODE "su - $USER -c \"if [ ! -f ~/.ssh/id_rsa ]; then ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa; fi\""
    done
    
    # Krok 2: Kopiowanie z kazdego wezla do kazdego innego (Full Mesh) / Step 2: Copying from each node to every other node (Full Mesh)
    for SOURCE_NODE in $NODES; do
        for TARGET_NODE in $NODES; do
            echo "Kopiowanie klucza z $SOURCE_NODE do $TARGET_NODE... / Copying key from $SOURCE_NODE to $TARGET_NODE..."
            sshpass -p "$LAB_PASS" ssh -o StrictHostKeyChecking=no root@$SOURCE_NODE "su - $USER -c \"sshpass -p '$LAB_PASS' ssh-copy-id -o StrictHostKeyChecking=no $USER@$TARGET_NODE\""
            sshpass -p "$LAB_PASS" ssh -o StrictHostKeyChecking=no root@$SOURCE_NODE "su - $USER -c \"sshpass -p '$LAB_PASS' ssh-copy-id -o StrictHostKeyChecking=no $USER@${TARGET_NODE}.lab.local\""
        done
    done
    
    # Krok 3: Testowanie / Step 3: Testing
    echo "Testowanie połączeń SSH bez hasła... / Testing passwordless SSH connections..."
    for SOURCE_NODE in $NODES; do
        for TARGET_NODE in $NODES; do
            sshpass -p "$LAB_PASS" ssh -o StrictHostKeyChecking=no root@$SOURCE_NODE "su - $USER -c \"ssh -o PasswordAuthentication=no $TARGET_NODE date\"" > /dev/null
            if [ $? -eq 0 ]; then
                echo "   [SUCCESS] $SOURCE_NODE -> $TARGET_NODE"
            else
                echo "   [FAILED] $SOURCE_NODE -> $TARGET_NODE"
            fi
        done
    done
}

# Wywołanie dla grid (tylko na nodach RAC) / Call for grid (RAC nodes only)
setup_full_mesh "grid" "$GRID_NODES"

# Wywołanie dla oracle (na nodach RAC, Standby, Infra) / Call for oracle (RAC, Standby, Infra nodes)
setup_full_mesh "oracle" "$ORACLE_NODES"

echo "=========================================================="
echo "    Gotowe! SSH User-Equivalency skonfigurowane w siatce. "
echo "    Done! SSH User-Equivalency configured in a mesh.      "
echo "=========================================================="
