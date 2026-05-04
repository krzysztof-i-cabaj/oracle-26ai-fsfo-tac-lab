# 🏗️ DESIGN — Recovery Appliance (ZDLRA-like) subproject

[![Doc Type](https://img.shields.io/badge/Type-Architecture-blueviolet)]()
[![ADRs](https://img.shields.io/badge/ADRs-6-success)]()
[![Status](https://img.shields.io/badge/Status-Approved-green)]()
[![Sprint](https://img.shields.io/badge/Sprints-0%20%7C%201%20%7C%202%20%7C%203-orange)]()
[![Compat](https://img.shields.io/badge/Oracle-26ai_23.26.1-red)]()
[![OS](https://img.shields.io/badge/OL-8.10-orange)]()

> 📐 Architecture decisions, compatibility, security, iteration plan.

## 1. 🎯 Context

The `VMs2-install` lab covers HA (RAC) + DR (Active DG + FSFO + TAC), but the backup layer is missing.
Closing the full MAA stack is a natural educational extension. ZDLRA, as a commercial appliance,
cannot be installed in VBox — we simulate its key features via plain RMAN + DG redo transport.

## 2. 📋 Architecture Decision Records

### ADR-001: Single Instance + systemd instead of Oracle Restart

- **Status:** Accepted
- **Date:** 2026-05-01
- **Context:** rcat01 is a small VM for the RMAN catalog (4 GB RAM). Grid Infrastructure for Standalone Server
  (Oracle Restart) provides automatic instance restart after a crash, but adds ~3 GB RAM overhead and a second binary install.
- **Decision:** A plain Single Instance + a systemd unit `oracle-rcat.service` that calls `dbstart`/`dbshut`.
  Auto-start after OS reboot is sufficient for this use-case; a single VM rarely crashes internally.
- **Consequences:** Less RAM, simpler installation, no Oracle-managed instance monitoring.
  If we discover we need automatic restart after a DB crash → migration to Oracle Restart in iteration v2.
- **Rejected alternatives:** Grid Infrastructure for Standalone Server (too much overhead);
  a plain `@reboot` in oracle's crontab (less standard than systemd).

### ADR-002: Subproject extracted as standalone `ZDLRA_like/` (top-level in oracle-26ai-fsfo-tac-lab repo)

- **Status:** Accepted (revised 2026-05-04 — extraction from `VMs2-install/_RecoveryAppliance_/` to standalone repo folder)
- **Date:** 2026-05-01 (initial) / 2026-05-04 (revised — repo extraction)
- **Context:** Originally a subdirectory **inside** `VMs2-install/_RecoveryAppliance_/` (part of the same lab installation), but designed self-contained from the start. After Sprints 0-3 completion + autonomous test session, the subproject was extracted as **top-level `ZDLRA_like/` folder** in [oracle-26ai-fsfo-tac-lab](https://github.com/krzysztof-i-cabaj/oracle-26ai-fsfo-tac-lab) GitHub repo for easier reference and standalone use.
- **Decision:** **`ZDLRA_like/` is the project root.** Self-contained — every file needed (scripts, sql, docs, kickstart, response_files) is inside this folder; no runtime dependencies on parent. Parent project (FSFO/TAC LAB) is referenced for context only (PRIM database, SSH equivalency, `LAB_PASS` convention).
- **Consequences:** Slight code duplication carried over from the original co-location (e.g. `setup_oracle_env.sh` copied with adjustments). Now `ZDLRA_like/` can be cloned/used independently; `VMs2-install/` is referenced as conceptual parent (not filesystem parent).

### ADR-003: ZDLRA-like, not ZDLRA

- **Status:** Accepted
- **Date:** 2026-05-01
- **Context:** ZDLRA is a closed-source appliance (hardware + RA Software). It cannot be installed
  in VBox. However, we can simulate its key features (incremental merge, real-time redo, compression).
- **Decision:** Naming everywhere is **"ZDLRA-like simulation"**. The docs clearly mark the boundary:
  what we simulate (incremental merge, virtual full, real-time redo), what we do NOT (block dedup, tape-out, RA replication).
- **Consequences:** Educationally clear; no pretence of being a real ZDLRA.

### ADR-004: Sprint 0 — VBoxManage keyboardputscancode as a proof-of-concept

- **Status:** Accepted
- **Date:** 2026-05-01
- **Context:** All existing VMs in the LAB require manual GRUB editing (TAB + payload) during ISO boot.
  The Recovery Appliance is a good candidate to test the automation concept — a single VM, easy to verify.
- **Decision:** Sprint 0 implements `Send-VBoxKeystrokes` in PowerShell + an orchestrator for rcat01.
  If it works, the scheme will move to a separate mini-project `_KickstartAutomation_/` for the remaining VMs.
- **Consequences:** Full automation of the rcat01 boot (zero user clicks). Timing/keyboard-layout risk —
  handled in the script via a retry loop and a US-keyboard scancode table.

### ADR-006: `/root/.lab_secrets` + `$LAB_PASS` convention

- **Status:** Accepted
- **Date:** 2026-05-01
- **Context:** Early script versions hardcoded `Oracle26ai_LAB!` in many places.
  The parent project `VMs2-install/` already has a `/root/.lab_secrets` convention with `export LAB_PASS=...`,
  used by `create_standby_broker.sh`, `setup_observer.sh` etc.
- **Decision:** The Recovery Appliance follows the same convention:
  - kickstart `ks-rcat01.cfg` in `%post` creates `/root/.lab_secrets` (chmod 600) + `/home/oracle/.lab_secrets`
  - all `.sh` scripts start with a source + `$LAB_PASS` validation block
  - SQL `01_create_catalog_schema.sql` accepts the password as a positional `&1`, the bash caller passes `${LAB_PASS}`
  - PowerShell Write-Host info points at `/root/.lab_secrets` instead of the literal password
- **Consequences:** Consistency with the parent project. Easy password rotation (one file). No hardcodes in git.
- **Rejected alternatives:** hardcode in scripts (insecure); env var in cron (cron has no terminal);
  mkstore/wallet (overkill for the LAB).

### ADR-005: Local backup target + vboxsf shared folder

- **Status:** Accepted
- **Date:** 2026-05-01
- **Context:** `/mnt/rman_bck` is already mounted as vboxsf on infra01/prim01/prim02/stby01 and points
  at a Windows host shared folder. This allows backups to be taken from PRIM directly into that directory.
- **Decision:** Physical backups are written to `/mnt/rman_bck/` (host shared folder); the RMAN metadata catalog
  lives in PDB `RCATPDB` on rcat01. The local 200 GB disk on rcat01 holds the catalog DB + FRA + archivelog cache.
- **Consequences:** Backups survive the destruction of all VMs (they live on the Windows host). vboxsf performance
  is lower than a native disk — acceptable for the LAB.

## 3. 🔌 Compatibility

| Component | Version | Notes |
|---|---|---|
| Oracle Database | 26ai 23.26.1 SE2/EE | Consistent with PRIM/STBY |
| Oracle Linux | 8.10 | Same ISO as the rest |
| Linux kernel | UEK7 (default OL 8.10) | Supported by the 23ai preinstall RPM |
| RMAN catalog DB version | 26ai (23.26.1) | Must be >= TARGET DB version (PRIM = 23.26.1) — OK |
| VirtualBox | 7.x | `VBoxManage` command line is compatible |
| `keyboardputscancode` | VBox 6.0+ | Stable API for many years |

## 4. 🔐 Security

- **Passwords** — convention **`$LAB_PASS` from `/root/.lab_secrets`** (chmod 600), consistent with `VMs2-install/scripts/`.
  The file is created automatically by kickstart (`%post`) on rcat01 + a copy in `/home/oracle/.lab_secrets`.
  All `.sh` scripts source the secrets at the top and validate that `$LAB_PASS` is not empty.
  In production: Oracle Wallet / JCEKS / Vault.
- **Catalog connections** from PRIM: TNS via the listener on rcat01:1521, password from `$LAB_PASS`
- **SQL** with SQL*Plus DEFINE: `01_create_catalog_schema.sql` accepts `$LAB_PASS` as the positional parameter `&1`
- No TDE in the first iteration (separate scenario in the future)
- Backups are unencrypted in the first iteration
- `firewall --disabled` on rcat01 (LAB convention)

## 5. 🧪 Tests

8 scenarios in `docs/08_Backup_Restore_Scenarios.md`:
B-1 (basic catalog), B-2 (weekly cycle), B-3 (incremental merge),
B-4 (PITR after DROP), B-5 (tablespace recovery), B-6 (controlfile loss),
B-7 (DG rebuild from backup), B-8 (DUPLICATE for test env).

## 6. 🚀 Iteration plan

| Sprint | Scope | Effort |
|---|---|---|
| 0 | Boot automation PoC (keyboardputscancode) | ~0.5 day |
| 1 | VM `rcat01` + DB + catalog + auto-start | ~1 day |
| 2 | Backup policy + scenarios B-1, B-2, B-4, B-5, B-6 | ~1 day |
| 3 | ZDLRA-like simulation + scenarios B-3, B-7, B-8 | ~1.5 days |
