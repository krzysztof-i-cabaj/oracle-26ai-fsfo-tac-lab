> 🇬🇧 English | [🇵🇱 Polski](./01_Architecture_and_Assumptions_PL.md)

# 01 — Environment Architecture and Main Assumptions (VMs2-install)

> **Goal:** Define the new virtual machine structure for Oracle 26ai (23.26.1) accounting for Data Guard (Primary 2-node RAC -> Standby Single Instance with Oracle Restart), FSFO (3 Observers) and TAC.
> **Note:** This environment is based on lessons learned from previous installations (including RAM allocation).

---

## 1. Virtual machine topology (5 VMs)

The whole environment consists of 5 virtual machines in VirtualBox.

| VM | Hostname | Role | vCPU | RAM | OS Disk | Additional resources |
|----|----------|------|------|-----|---------|-------------------|
| **VM1** | `prim01.lab.local` | RAC node 1 (Primary DC) | 4 | **9 GB** | 60 GB | iSCSI initiator (attached ASM LUNs) |
| **VM2** | `prim02.lab.local` | RAC node 2 (Primary DC) | 4 | **9 GB** | 60 GB | iSCSI initiator (attached ASM LUNs) |
| **VM3** | `stby01.lab.local` | Single Instance (Standby DR) with **Oracle Restart** | 4 | **8 GB** | 100 GB | XFS for the database, Oracle Restart manages services |
| **VM4** | `infra01.lab.local`| DNS, NTP, iSCSI Target, **Master Observer (EXT)** | 2 | **8 GB** | 140 GB | LIO Cache memory (8GB RAM), LUNs for prim01/02 |
| **VM5** | `client01.lab.local`| Client for testing TAC (Java/UCP) | 2 | 3 GB | 30 GB | Oracle Client 23.26 |

*RAM sizes have been adjusted (increased for prim01/02 to 9GB due to `cluvfy` restrictions in 26ai, and infra01/stby01 for page cache and Oracle Restart performance).*

---

## 2. Global lab parameters

For management simplicity we use consistent naming and passwords across the entire lab:

*   **Password for all OS accounts (`root`, `oracle`, `grid`) and Oracle DB accounts (`SYS`, `SYSTEM`):**
    *   `Oracle26ai_LAB!`
*   **Public network (vboxnet0):** `192.168.56.0/24`
*   **Private/Interconnect network (rac-priv):** `192.168.100.0/24`
*   **iSCSI/Storage network (rac-storage):** `192.168.200.0/24`
*   **CDB / PDB Name:** `PRIM` / `APPPDB`
*   **DB_UNIQUE_NAME (Primary / Standby):** `PRIM` / `STBY`
*   **Service Name for TAC:** `MYAPP_TAC`

---

## 3. Network and IP Addressing (Details)

All machines use static IP addresses in VirtualBox subnets. On the `infra01` machine a DNS server (`bind9`) will be running, providing name resolution for all hosts and the Primary cluster's SCAN addresses.

### IP address mapping:
| Hostname | Public (56.x) | Interconnect (100.x) | Storage (200.x) |
|----------|---------------|----------------------|-----------------|
| `infra01`| .10 | .10 | .10 |
| `prim01` | .11 | .11 | .11 |
| `prim02` | .12 | .12 | .12 |
| `stby01` | .13 | - | - |
| `client01`| .15 | - | - |

**Virtual IP addresses (Grid Managed):**
*   `prim01-vip`: `192.168.56.21`
*   `prim02-vip`: `192.168.56.22`
*   `scan-prim`: `192.168.56.31`, `192.168.56.32`, `192.168.56.33` (DNS round-robin)

---

## 4. Observer configuration (FSFO)

The architecture assumes 3 Observers to provide the highest availability of the FSFO mechanism:
1.  **Master Observer (`obs_ext`)**: Running on the `infra01` machine (simulating a third site - EXT).
2.  **Backup Observer 1 (`obs_dc`)**: Running on the `prim01` node (DC).
3.  **Backup Observer 2 (`obs_dr`)**: Running on the `stby01` node (DR).

---

## 4.1 Oracle licensing requirements (F-21)

> **Note:** the requirements below apply to a **real production deployment**. The LAB on your own OL 8.10 / VirtualBox is covered solely by the *Developer License* (for learning, internal testing, technical demos — without running production workload).

| Component / feature | Required Oracle license |
|----|----|
| Grid Infrastructure (cluster) | **Database Enterprise Edition** + **RAC option** |
| 2-node Primary cluster (prim01+prim02) | **Real Application Clusters** (RAC) |
| Data Guard (Physical Standby) | **Database Enterprise Edition** (DG itself without ADG fits within EE) |
| `MYAPP_RO` on stby01 (read-only access to standby) | **Active Data Guard** (additional option) |
| Transparent Application Continuity (TAC) | EE + RAC (TAC builds on Application Continuity, available since 12.2 EE) |
| `DBMS_APP_CONT.GET_LTXID_OUTCOME` / Transaction Guard | EE (base part) |
| FSFO + Observer (DG Broker) | EE (Broker in EE database) |
| `V$ACTIVE_SESSION_HISTORY`, `DBA_HIST_*` (AWR/ASH in monitors) | **Diagnostic Pack** (separate license) |
| `DBMS_SQLTUNE`, SQL Tuning Advisor | **Tuning Pack** (separate license) |
| Oracle Wallet / TDE (if enabled) | **Advanced Security Option** |

**Practical consequences for VMs2-install:**
- Diagnostic scripts use `V$ACTIVE_SESSION_HISTORY` (e.g. `tac_replay_monitor_26ai.sql` section 6) — **requires Diagnostic Pack** in production. In the LAB it works without warnings.
- The read-only service (`MYAPP_RO`) on stby01 uses Active Data Guard — in production only after purchasing ADG; **if you do not have ADG, remove `MYAPP_RO` from the configuration** or keep stby01 in MRP-only mode (Apply Only) without open read-only.
- TAC + RAC option must be licensed per-core (Named User Plus or Processor metric).

---

## 5. New approach: Oracle Restart for Standby and DGMGRL DUPLICATE

*   **Oracle Restart on `stby01`**: Instead of a clean install of just the database, we will use the **Grid Infrastructure for a Standalone Server** installation. This will allow creation of CRS services managing automatic startup of the `STBY` database and the dedicated DGMGRL listener after a machine restart.
*   **DGMGRL DUPLICATE**: The Standby database creation process will be fully automated using Data Guard Broker (the `CREATE CONFIGURATION` command followed by `DUPLICATE`). We eliminate writing RMAN scripts.

---
**Next step:** `02_OS_and_Network_Preparation.md`
