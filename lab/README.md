# Project: VMs2-install (Oracle 26ai MAA Environment)

Welcome to the revised and standardized deployment guide for the **Oracle 26ai (23.26.1)** environment, built on the Maximum Availability Architecture (MAA).

The main goal of this sub-project was to draw lessons from previous installations (including numerous "FIX" patches for 26ai) and create a linear, error-free, and automated installation path — from bare virtual machines all the way to testing the **Transparent Application Continuity (TAC)** mechanism on a cluster equipped with **Fast-Start Failover (FSFO)**.

---

## Notation and file transfer

Scripts and configuration files are stored on the Windows host in the project directory:
`<REPO>`

**Before each installation step**, copy the required subdirectories to the target Linux server via MobaXterm (SFTP) or `scp`:
```
# Copying via scp from the Windows host (Git Bash / PowerShell with OpenSSH):
scp -r scripts/ response_files/ sql/ src/ root@prim01:/tmp/
```
After copying, the files are available under `/tmp/scripts/`, `/tmp/response_files/`, etc.
All commands in `docs/` use `/tmp/` as the working location.

> PowerShell commands (e.g. `vbox_create_vms.ps1`) are run directly on the Windows host — they do not need to be copied.

---

## Directory Structure

Instead of pasting scripts manually, the entire deployment has been split into thematic resources:

*   **`docs/`** — Main step-by-step documentation (from 01 to 08).
*   **`kickstart/`** — Optimized Kickstart files for Oracle Linux 8. They enable LVM iSCSI Block Backstore for top performance, disable THP, and automatically mount shared directories (VirtualBox Shared Folders).
*   **`scripts/`** — Ready-made `bash` shell scripts for the environments. They configure the network, iSCSI targets, build the SSH authorization mesh, silently install the Grid/DB software, and create Standby databases via the Broker.
*   **`response_files/`** — A set of `.rsp` files precisely tailored to the strict schema of Oracle 26ai tooling (legacy 19c entries have been removed).
*   **`sql/`** — Diagnostic utilities running so-called *Readiness Checks* for the environment (e.g. checking the database's readiness for FAN/TAC notifications).
*   **`src/`** — Source code, including the Java UCP test client `TestHarness.java` which uses the `oracle.jdbc.replay.OracleDataSourceImpl` class to verify transparent session re-routing.

---

## Installation Roadmap

The build process is divided into 8 coherent steps. Execute them in the following order:

1.  **`01_Architecture_and_Assumptions.md`** — Memory requirements, ports, naming, and an initial overview of the machine topology.
2.  **`02_OS_and_Network_Preparation.md`** — Deploying the operating systems from prepared kickstarts, network testing, and building the Full Mesh SSH.
    - **`02b_OS_Preparation_Manual.md`** — Alternative to kickstart: all steps presented step-by-step for each host with copy/paste commands (network, users, directories, THP, HugePages, NTP, DNS).
3.  **`03_Storage_iSCSI.md`** — The heart of performance — creating iSCSI LVM Targets on the `infra01` server and connecting them as raw blocks to the RAC cluster.
4.  **`04_Grid_Infrastructure.md`** — Installation of `Grid Infrastructure` on `prim01/prim02` and the `Oracle Restart` software on the `stby01` node.
5.  **`05_Database_Primary.md`** — Installation of the DB engine (Software-Only) and creation of the `CDB PRIM` from a DBCA response file. ARCHIVELOG and Flashback configuration.
6.  **`06_Data_Guard_Standby.md`** — Modern, automated creation of the standby database using the built-in Broker command (`CREATE PHYSICAL STANDBY`).
7.  **`07_FSFO_Observery.md`** — Installation of the 26ai Client, setting up passwordless auto-login to the SSO Wallet, and activation of Fast-Start Failover.
8.  **`08_TAC_and_Tests.md`** — The final check. Configuration of the application service, cross-site ONS, and running a simulated fault in Java UCP.
9.  **`09_Test_Scenarios.md`** — A set of scenarios demonstrating the resilience of the architecture (Switchover, unplanned Failover, long-running TAC Replay, and Apply Lag blocking).

---

## Before the first run (PRE-FLIGHT)

> Whether you take the **automated path** (scripts) or the **manual path** (step-by-step from `docs/`), perform the points below once before starting — **in this order**.

1. **Lab secret** (`/root/.lab_secrets`) — on **every host** where you run `bash` scripts (ssh_setup.sh, setup_observer.sh, create_standby_broker.sh, setup_cross_site_ons.sh, tune_storage_runtime.sh):
   ```bash
   sudo tee /root/.lab_secrets >/dev/null <<'EOF'
   export LAB_PASS='Oracle26ai_LAB!'
   EOF
   sudo chmod 600 /root/.lab_secrets
   ```
   The scripts read this file themselves (`source /root/.lab_secrets`) — no need for `sudo -E` or exporting the variable in the shell. The same password is used for all accounts (root/oracle/grid/SYS/SYSTEM/ASM/PDB Admin/wallet) — the LAB convention is described in `docs/01_Architektura_i_Zalozenia.md` section 2.

2. **DNS and NTP** — the infra01 kickstart configures `bind9` (zone `lab.local`) and `chrony` (NTP server) automatically after reboot. The kickstarts for the other VMs set chrony as a client (`192.168.56.10`) and force the DNS resolver on `enp0s3` (a safeguard against being overwritten by DHCP NAT). **Nothing needs to be done manually.** If DNS is not working after a reboot — see `docs/02` section 4 (fallback).

3. **Environment validation** — **after DNS and chrony**, before `gridSetup.sh`, run on **prim01** (as oracle or grid) and optionally on **stby01**:
   ```bash
   # prim01 (as oracle) — comprehensive check, including SSH equivalency to prim02/stby01:
   bash /tmp/scripts/validate_env.sh --full
   # stby01 (as oracle) — local check of DNS/NTP/HugePages/THP/memlock:
   bash /tmp/scripts/validate_env.sh --full
   ```
   The test covers: DNS, NTP, SSH equivalency, `/u01` mount, ASM disks, Oracle ports, HugePages, THP, memlock. All `PASS` statuses = you can move on. A `FAIL` = fix it before you start the GI install.

   > **memlock WARN?** The kickstart creates `zz-oracle-memlock.conf` (the `zz-` prefix > `oracle-database-preinstall-23ai.conf` — it always wins). If you installed from an older kickstart, create this file manually — see `docs/02` section 4c.

4. **Performance (optional but recommended)** — after configuring iSCSI:
   ```bash
   sudo bash /tmp/scripts/tune_storage_runtime.sh --target=infra        # on infra01
   sudo bash /tmp/scripts/tune_storage_runtime.sh --target=initiator    # on prim01 and prim02
   ```
   Details in `docs/10_Performance_Tuning.md`.

> **Consistency between the two paths:** the automated path (scripts) and the manual one (commands from `docs/`) use **the same** configuration files (`response_files/*.rsp`, `kickstart/*.cfg`) and lead to an identical end state. You can switch between them between steps (e.g. perform GI with the auto-script, but create the standby manually following `docs/06`).

---

Happy installing!
