> 🇬🇧 English | [🇵🇱 Polski](./04_Grid_Infrastructure_PL.md)

# 04 — Grid Infrastructure Installation (VMs2-install)

> **Goal:** Install Oracle Grid Infrastructure 26ai (23.26.1) software. We will do this in two variants: on the RAC cluster (`prim01` and `prim02`) as full Clusterware, and on the Standby machine (`stby01`) as **Oracle Restart** (Standalone Server) for service management.

This document describes two deployment methods: automated (script-driven) and fully manual step by step.

---

## 1. Prerequisites (Prereq)

1.  Shared disks mapped on `prim01` and `prim02` as `/dev/oracleasm/OCR*`, `DATA1`, `RECO1` (step 03_Storage).
2.  Passwordless SSH relationships built for users `oracle` and `grid` between machines (step 02_Preparation).
3.  DNS installed and running on `infra01`, correctly resolving the SCAN cluster name (`scan-prim.lab.local`).
4.  Environment profiles configured (`ORACLE_HOME`, `PATH`) for users `grid` and `oracle` on all nodes — run **once** as root on `prim01`:
    ```bash
    sudo bash /tmp/scripts/setup_oracle_env.sh
    ```
    The script sets `.bash_profile` on `prim01`, `prim02` and `stby01` and fixes ownership of `/etc/oraInst.loc` (required by CVU). Idempotent — safe to re-run.

### Installation files from the host (Windows)
The `.cfg` files (kickstart) include the `/mnt/oracle_binaries` mount point. These bundles should contain the 23.26 Grid installer ZIP (`V1054596-01...zip`).

---

## Method 1: Automated Fast Path (Recommended)

The `install_grid_silent.sh` script automates decompression (Image Install) and installer invocation with the appropriate flags to bypass warnings.

### 2. Grid Infrastructure installation for 2-node RAC (prim01, prim02)

1.  Log in to `prim01` as user `grid`:
    ```bash
    su - grid
    bash /tmp/scripts/install_grid_silent.sh /tmp/response_files/grid_rac.rsp
    ```

2.  When the installer finishes the software phase and displays the message:
    ```
    Successfully Setup Software.
    As install user, run the following command to complete the configuration.
            /u01/app/23.26/grid/gridSetup.sh -executeConfigTools ...
    ```
    **Do not run executeConfigTools yet** — root scripts first. Open a new terminal on `prim01` as `root`:
    ```bash
    /u01/app/oraInventory/orainstRoot.sh
    /u01/app/23.26/grid/root.sh
    ```
    **Wait for root.sh to finish on prim01 before proceeding (5–15 min).**

3.  Then on node `prim02` as `root` (only after prim01 finishes!):
    ```bash
    /u01/app/23.26/grid/root.sh
    ```
    **Wait for completion.**

4.  Return to `prim01` as `grid` and run the configuration tools (executeConfigTools):
    ```bash
    export CV_ASSUME_DISTID=OEL8.10
    /u01/app/23.26/grid/gridSetup.sh -executeConfigTools \
        -responseFile /tmp/response_files/grid_rac.rsp -silent
    ```

### 2a. Creating diskgroups +DATA and +RECO

`grid_rac.rsp` creates only `+OCR`. Before installing the database (step 05) create `+DATA` and `+RECO` — DBCA assumes their existence.

As **`grid@prim01`**:

```bash
# +DATA (EXTERNAL redundancy — 1 disk)
asmca -silent -createDiskGroup \
    -diskGroupName DATA \
    -diskList /dev/oracleasm/DATA1 \
    -redundancy EXTERNAL \
    -au_size 4 \
    -sysAsmPassword 'Oracle26ai_LAB!'

# +RECO (EXTERNAL redundancy — 1 disk)
asmca -silent -createDiskGroup \
    -diskGroupName RECO \
    -diskList /dev/oracleasm/RECO1 \
    -redundancy EXTERNAL \
    -au_size 4 \
    -sysAsmPassword 'Oracle26ai_LAB!'

# Verification — expected: OCR (NORMAL) + DATA (EXTERN) + RECO (EXTERN), all MOUNTED
asmcmd lsdg
```

### 3. Oracle Restart installation on stby01 (Standalone)

> `grid_restart.rsp` uses `installOption=CRS_SWONLY` — installs binaries without storage validation. Oracle GI 23.26.1 ignores `FILE_SYSTEM_STORAGE` in `HA_CONFIG` mode (always requires ASM disks — INS-30507), which is why we use `CRS_SWONLY`. After `root.sh` (base OS setup), OHAS configuration is performed by `roothas.pl`.

1.  Log in to `stby01` as user `grid`:
    ```bash
    su - grid
    bash /tmp/scripts/install_grid_silent.sh /tmp/response_files/grid_restart.rsp
    ```

2.  After the "Successfully Setup Software" message, on `stby01` as `root`:
    ```bash
    /u01/app/23.26/grid/root.sh
    ```
    `root.sh` for `CRS_SWONLY` only performs base OS setup (oraenv, oratab) — **it does not configure OHAS**.

3.  Oracle Restart configuration (OHAS) — as `root` on `stby01`:
    ```bash
    /u01/app/23.26/grid/perl/bin/perl \
        -I /u01/app/23.26/grid/perl/lib \
        -I /u01/app/23.26/grid/crs/install \
        /u01/app/23.26/grid/crs/install/roothas.pl
    ```
    Expected message: `CLSRSC-327: Successfully configured Oracle Restart for a standalone server`

Proceed to section **4. Installation Verification**.

---

## Method 2: Manual Path (Step by step)

For manual installation we run the process with explicit commands for the Image Install. Remember to set system variables that bypass OS validators.

### 2. Grid Infrastructure installation for 2-node RAC (prim01, prim02)

Log in to `prim01` as user `grid`.

```bash
# Set the variable that fools the distribution validator
export CV_ASSUME_DISTID=OEL8.10
export GRID_HOME=/u01/app/23.26/grid

# Decompress the installation file using Image Install mode
mkdir -p $GRID_HOME
cd $GRID_HOME
unzip -q /mnt/oracle_binaries/V1054596-01-OracleDatabase23.26.1.0.0forLinux_x86-64.zip

# Silent cluster installation using the previously prepared RSP
./gridSetup.sh -silent -ignorePrereqFailure -responseFile /tmp/response_files/grid_rac.rsp
```

When the installer returns the message about running ROOT scripts:
Log in to **`prim01`** as `root`:
```bash
/u01/app/23.26/grid/root.sh
```
Wait for successful completion (creation of the local ASM OCR). Then log in to **`prim02`** as `root`:
```bash
/u01/app/23.26/grid/root.sh
```

Return to the `grid` account on `prim01` and invoke the script that finishes the installation, to update the Oracle Inventory.
```bash
/u01/app/23.26/grid/gridSetup.sh -executeConfigTools -responseFile /tmp/response_files/grid_rac.rsp -silent
```

### 2a. Creating diskgroups +DATA and +RECO

```bash
asmca -silent -createDiskGroup \
    -diskGroupName DATA \
    -diskList /dev/oracleasm/DATA1 \
    -redundancy EXTERNAL \
    -au_size 4 \
    -sysAsmPassword 'Oracle26ai_LAB!'

asmca -silent -createDiskGroup \
    -diskGroupName RECO \
    -diskList /dev/oracleasm/RECO1 \
    -redundancy EXTERNAL \
    -au_size 4 \
    -sysAsmPassword 'Oracle26ai_LAB!'

asmcmd lsdg
```

### 3. Oracle Restart installation on stby01 (Standalone)

> `grid_restart.rsp` uses `installOption=CRS_SWONLY` — no storage validation. `root.sh` for `CRS_SWONLY` only performs base OS setup — OHAS is configured by `roothas.pl`.

Log in to `stby01` as user `grid`.

```bash
export CV_ASSUME_DISTID=OEL8.10
export GRID_HOME=/u01/app/23.26/grid

mkdir -p $GRID_HOME
cd $GRID_HOME
unzip -q /mnt/oracle_binaries/V1054596-01-OracleDatabase23.26.1.0.0forLinux_x86-64.zip

./gridSetup.sh -silent -ignorePrereqFailure -responseFile /tmp/response_files/grid_restart.rsp
```

After the "Successfully Setup Software" message, as `root` on **`stby01`**:
```bash
/u01/app/23.26/grid/root.sh

# Oracle Restart configuration (OHAS) — root.sh for CRS_SWONLY does not configure OHAS:
/u01/app/23.26/grid/perl/bin/perl \
    -I /u01/app/23.26/grid/perl/lib \
    -I /u01/app/23.26/grid/crs/install \
    /u01/app/23.26/grid/crs/install/roothas.pl
# Expected: CLSRSC-327: Successfully configured Oracle Restart for a standalone server
```

---

## 4. Installation Verification

> **If `crsctl: command not found`** — the `grid` user profile does not have `ORACLE_HOME` set. Set it once (or check section 2.14 in `02b_OS_Preparation_Manual.md`):
> ```bash
> export ORACLE_HOME=/u01/app/23.26/grid
> export PATH=$ORACLE_HOME/bin:$PATH
> ```
>
> **If `sqlplus / as sysasm` returns ORA-12162** — `ORACLE_SID` is missing. Set it before invoking sqlplus:
> ```bash
> export ORACLE_SID=+ASM1   # prim01; on prim02: +ASM2; on stby01: +ASM
> ```

Verify RAC cluster status (on **`prim01`** as `grid`):
```bash
crsctl stat res -t
```
You should see running services and mounted disk groups (`ora.OCR.dg`).

Verify Oracle Restart status (on **`stby01`** as `grid`):
```bash
crsctl check has
# Expected output: CRS-4638: Oracle High Availability Services is online
```

This way the primary environment runs on RAC cluster High Availability, while the Standby environment will be able to automatically and reliably manage operation of the local database instance and its network.

---
**Next step:** `05_Database_Primary.md`
