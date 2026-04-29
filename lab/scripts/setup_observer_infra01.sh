#!/bin/bash
# ==============================================================================
# Tytul:        setup_observer_infra01.sh (wrapper)
# Opis:         Backward-compat wrapper. Real installer = setup_observer.sh.
#               Wywoluje go z defaultami dla Master Observera (obs_ext na infra01).
# Description [EN]: Backward-compat wrapper. Real installer = setup_observer.sh,
#               called with Master Observer defaults (obs_ext on infra01).
#
# Autor:        KCB Kris
# Data:         2026-04-27
# Wersja:       3.0 (VMs2-install) - F-03 multi-Observer refactor
#
# Uzycie:       sudo bash setup_observer_infra01.sh
# Usage:        sudo bash setup_observer_infra01.sh
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/setup_observer.sh" "$@"
