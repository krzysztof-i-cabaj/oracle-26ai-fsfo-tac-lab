> 🇬🇧 English | [🇵🇱 Polski](./ARCHITECTURE_DIAGRAMS_PL.md)

# VMs2-install Architecture — Mermaid Diagrams

> Visual companion to the documentation in `01_Architecture_and_Assumptions.md`. Each diagram shows a different layer / aspect of the Oracle 26ai HA solution (RAC + Active Data Guard + FSFO + TAC).
>
> The diagrams render natively on GitHub, GitLab, VS Code (with the Markdown Preview Mermaid Support extension), Obsidian, and most modern Markdown viewers.

**Diagram index:**
1. [Virtual machine topology](#1-virtual-machine-topology-5-vms)
2. [Networks and IP addressing](#2-networks-and-ip-addressing-vboxnet--internal)
3. [iSCSI + LVM + ASM storage stack](#3-iscsi--lvm--asm-storage-stack-block-backstore)
4. [Data Guard + Broker + redo transport](#4-data-guard--broker--redo-transport)
5. [Multi-Observer FSFO (Master + 2 Backup)](#5-multi-observer-fsfo-master--2-backup)
6. [TAC + UCP client + FAN events](#6-tac--ucp-client--fan-events)
7. [Sequence: unplanned failover (FSFO)](#7-sequence-unplanned-failover-fsfo)
8. [Sequence: planned switchover](#8-sequence-planned-switchover)
9. [Security: wallets and passwords](#9-security-wallets-and-passwords)
10. [Network port matrix](#10-network-port-matrix-firewall)

---

## 1. Virtual machine topology (5 VMs)

```mermaid
flowchart TB
    subgraph host["Host Windows 11 + VirtualBox 7.x"]
        direction TB

        subgraph infra["infra01 — Infrastructure & Master Observer"]
            DNS["bind9 DNS<br/>lab.local"]
            NTP["chronyd"]
            ISCSI_T["iSCSI Target<br/>LIO + LVM"]
            OBS_EXT["Master Observer<br/>obs_ext"]
            CLIENT["Oracle Client 23.26<br/>+ mkstore + dgmgrl"]
        end

        subgraph rac["RAC Primary Cluster (DC)"]
            direction LR
            subgraph prim01["prim01 (RAC node 1)"]
                GI1["Grid Infrastructure"]
                DB1["Oracle DB 23.26<br/>instance PRIM1"]
                OBS_DC["Backup Observer<br/>obs_dc"]
                ASM1["ASM disks<br/>+DATA / +RECO"]
            end
            subgraph prim02["prim02 (RAC node 2)"]
                GI2["Grid Infrastructure"]
                DB2["Oracle DB 23.26<br/>instance PRIM2"]
                ASM2["ASM disks<br/>+DATA / +RECO"]
            end
        end

        subgraph stby["stby01 — Active Data Guard (DR)"]
            GIR["Oracle Restart<br/>(GI Standalone)"]
            DBSTBY["Oracle DB 23.26<br/>STBY<br/>READ ONLY WITH APPLY"]
            OBS_DR["Backup Observer<br/>obs_dr"]
            XFS["Local XFS<br/>/u02 + /u03"]
        end

        subgraph client01["client01 — Application Test"]
            JAVA["OpenJDK 17"]
            UCP["TestHarness.java<br/>UCP + ojdbc11 + ucp11"]
        end

        DB1 -. "RAC interconnect" .- DB2
        DB1 -- "Redo SYNC<br/>(MaxAvailability)" --> DBSTBY
        DB2 -. "Redo SYNC" .-> DBSTBY

        OBS_EXT -- "DGMGRL ping" --> DB1
        OBS_EXT -- "DGMGRL ping" --> DBSTBY
        OBS_DC -. "Backup" .- OBS_EXT
        OBS_DR -. "Backup" .- OBS_EXT

        UCP -- "JDBC<br/>MYAPP_TAC" --> DB1
        UCP -- "JDBC<br/>MYAPP_TAC" --> DB2
        UCP -- "FAN events<br/>ONS:6200" --> OBS_EXT

        ASM1 -. "iSCSI" .-> ISCSI_T
        ASM2 -. "iSCSI" .-> ISCSI_T
    end

    classDef infra fill:#e1f5ff,stroke:#0288d1,color:#000
    classDef primary fill:#c8e6c9,stroke:#388e3c,color:#000
    classDef standby fill:#fff9c4,stroke:#f57f17,color:#000
    classDef client fill:#f3e5f5,stroke:#7b1fa2,color:#000

    class infra,DNS,NTP,ISCSI_T,OBS_EXT,CLIENT infra
    class prim01,prim02,GI1,GI2,DB1,DB2,OBS_DC,ASM1,ASM2 primary
    class stby,GIR,DBSTBY,OBS_DR,XFS standby
    class client01,JAVA,UCP client
```

**Legend:**
- 🟦 `infra01` — single infrastructure responsibilities (DNS, NTP, iSCSI Target, Master Observer)
- 🟩 RAC Primary (prim01+prim02) — 2-node cluster with ASM on shared storage
- 🟨 Active Data Guard (stby01) — Single Instance + Oracle Restart, local XFS
- 🟪 client01 — TestHarness UCP/TAC

---

## 2. Networks and IP addressing (vboxnet + internal)

```mermaid
flowchart LR
    subgraph public["192.168.56.0/24 — vboxnet (Host-Only)"]
        infra_pub["infra01 .10"]
        prim01_pub["prim01 .11<br/>vip .21"]
        prim02_pub["prim02 .12<br/>vip .22"]
        stby_pub["stby01 .13"]
        client_pub["client01 .15"]
        scan["scan-prim<br/>.31 .32 .33"]
    end

    subgraph priv["192.168.100.0/24 — Cluster Interconnect (internal)"]
        prim01_priv["prim01 .11"]
        prim02_priv["prim02 .12"]
    end

    subgraph storage["192.168.200.0/24 — Storage iSCSI MTU=9000 (internal)"]
        infra_stor["infra01 .10"]
        prim01_stor["prim01 .11"]
        prim02_stor["prim02 .12"]
    end

    subgraph nat["NAT — Internet egress (DHCP)"]
        all_nat["all VMs<br/>(yum/dnf updates)"]
    end

    prim01_priv <==> prim02_priv
    prim01_stor -- iSCSI --> infra_stor
    prim02_stor -- iSCSI --> infra_stor

    classDef pub fill:#bbdefb,stroke:#1976d2,color:#000
    classDef privnet fill:#ffccbc,stroke:#d84315,color:#000
    classDef stor fill:#c5cae9,stroke:#303f9f,color:#000
    classDef natnet fill:#e0e0e0,stroke:#616161,color:#000

    class public,infra_pub,prim01_pub,prim02_pub,stby_pub,client_pub,scan pub
    class priv,prim01_priv,prim02_priv privnet
    class storage,infra_stor,prim01_stor,prim02_stor stor
    class nat,all_nat natnet
```

> 💡 **MTU 9000 (jumbo frames)** on `enp0s9` (storage NIC) — F-18.D, delivers 1.5–2× sequential reads vs. MTU 1500.
> 💡 **Cluster interconnect** (`enp0s8`) is internal-only — there is no egress beyond VirtualBox; this protects against split-brain.

---

## 3. iSCSI + LVM + ASM storage stack (block backstore)

```mermaid
flowchart TB
    subgraph host["Host Windows 11 (VirtualBox)"]
        DISK_HOST["Physical host disk<br/>NTFS"]
    end

    subgraph infra01["infra01"]
        VDI_INFRA["VDI infra01-disk2<br/>100 GB"]
        SDB["/dev/sdb"]
        PV["LVM PV (pvcreate)"]
        VG["LVM VG vg_iscsi"]
        LV1["LV lun_ocr1"]
        LV2["LV lun_ocr2"]
        LV3["LV lun_ocr3"]
        LV4["LV lun_data1"]
        LV5["LV lun_reco1"]
        LIO["LIO Target<br/>(targetcli)<br/>iSCSI:3260"]
    end

    subgraph prim["prim01 / prim02 (initiator)"]
        ISCSI_INIT["iscsiadm session"]
        SCSI_DEV["/dev/sdc..g (mapped)"]
        UDEV["udev rules<br/>/dev/oracleasm/disks/*"]
        ASM["ASM Disk Groups<br/>+DATA (NORMAL redundancy)<br/>+RECO (NORMAL)<br/>+OCR (NORMAL)"]
        DBFILE["Oracle datafiles<br/>tablespaces, redo, control"]
    end

    DISK_HOST --> VDI_INFRA
    VDI_INFRA --> SDB
    SDB --> PV
    PV --> VG
    VG --> LV1
    VG --> LV2
    VG --> LV3
    VG --> LV4
    VG --> LV5
    LV1 -- "block backstore" --> LIO
    LV2 -- "block backstore" --> LIO
    LV3 -- "block backstore" --> LIO
    LV4 -- "block backstore<br/>write-back ON" --> LIO
    LV5 -- "block backstore<br/>write-back ON" --> LIO

    LIO -- "iSCSI 192.168.200.10:3260<br/>MTU 9000" --> ISCSI_INIT
    ISCSI_INIT --> SCSI_DEV
    SCSI_DEV --> UDEV
    UDEV --> ASM
    ASM --> DBFILE

    classDef raw fill:#ffe0b2,stroke:#ef6c00,color:#000
    classDef lvm fill:#dcedc8,stroke:#558b2f,color:#000
    classDef oracle fill:#bbdefb,stroke:#1565c0,color:#000

    class DISK_HOST,VDI_INFRA,SDB raw
    class PV,VG,LV1,LV2,LV3,LV4,LV5,LIO lvm
    class ISCSI_INIT,SCSI_DEV,UDEV,ASM,DBFILE oracle
```

> 💡 **Block backstore instead of fileio** = no filesystem layer in between (XFS/ext4) → 2–3× IOPS, no journal overhead. This is a PROD-like pattern (NetApp/Pure/EMC).
> 💡 **Write-back on DATA/RECO**, sync on **OCR** (voting disks must be consistent).
> 💡 **mq-deadline scheduler** on `/dev/sdb` (F-18.E) — better suited to iSCSI with concurrent writers.

---

## 4. Data Guard + Broker + redo transport

```mermaid
flowchart LR
    subgraph prim["PRIM (Primary RAC, MaxAvailability)"]
        direction TB
        LGWR1["LGWR<br/>(prim01)"]
        LGWR2["LGWR<br/>(prim02)"]
        LNS1["LNS<br/>(redo shipping)"]
        LNS2["LNS"]
        SRL["Standby Redo Logs<br/>(stby01)"]
        ARC["Archived Redo<br/>+RECO/PRIM/"]
    end

    subgraph stby["STBY (Single Instance + Oracle Restart)"]
        direction TB
        RFS["RFS<br/>(remote file server)"]
        SRL_S["Standby Redo Logs<br/>(local /u02)"]
        MRP["MRP<br/>(Managed Recovery Process)"]
        DBOPEN["Active DG<br/>READ ONLY WITH APPLY<br/>+ Real-Time Apply"]
    end

    subgraph broker["DG Broker (DGMGRL)"]
        BCONFIG["fsfo_cfg<br/>Protection Mode: MaxAvailability<br/>Configuration Status: SUCCESS"]
        BPRIM["Database PRIM<br/>role=PRIMARY<br/>StaticConnectIdentifier:1522"]
        BSTBY["Database STBY<br/>role=PHYSICAL_STANDBY<br/>StaticConnectIdentifier:1522<br/>State=APPLY-ON"]
    end

    LGWR1 --> SRL
    LGWR2 --> SRL
    LGWR1 --> LNS1
    LGWR2 --> LNS2
    LNS1 -- "SYNC<br/>(AFFIRM)" --> RFS
    LNS2 -- "SYNC<br/>(AFFIRM)" --> RFS
    RFS --> SRL_S
    SRL_S --> MRP
    MRP --> DBOPEN

    BCONFIG --- BPRIM
    BCONFIG --- BSTBY
    BPRIM -. "manages" .-> LGWR1
    BPRIM -. "manages" .-> LGWR2
    BSTBY -. "manages" .-> MRP

    classDef primarycolor fill:#c8e6c9,stroke:#388e3c,color:#000
    classDef standbycolor fill:#fff9c4,stroke:#f57f17,color:#000
    classDef brokercolor fill:#e1bee7,stroke:#6a1b9a,color:#000

    class prim,LGWR1,LGWR2,LNS1,LNS2,SRL,ARC primarycolor
    class stby,RFS,SRL_S,MRP,DBOPEN standbycolor
    class broker,BCONFIG,BPRIM,BSTBY brokercolor
```

**Key settings (from `create_standby_broker.sh`):**
- `LogXptMode='SYNC'` (Maximum Availability)
- `FastStartFailoverThreshold=30` s
- `FastStartFailoverLagLimit=0` (Zero Data Loss)
- `StaticConnectIdentifier` with explicit `PORT=1522` (FIX-096)
- `srvctl modify database -db STBY -startoption "READ ONLY"` + `SAVE STATE` PDB → persistent Active DG

---

## 5. Multi-Observer FSFO (Master + 2 Backup)

```mermaid
flowchart TB
    subgraph fsfo["DG Broker fsfo_cfg — Multi-Observer"]
        BCFG["FSFO ENABLED<br/>Threshold=30s<br/>LagLimit=0"]
    end

    subgraph infra01["infra01"]
        OBSEXT["obs_ext<br/>systemd: dgmgrl-observer-obs_ext.service<br/>Wallet: /etc/oracle/wallet/obs_ext<br/>STATUS: MASTER (active)"]
    end

    subgraph prim01["prim01"]
        OBSDC["obs_dc<br/>systemd: dgmgrl-observer-obs_dc.service<br/>Wallet: /etc/oracle/wallet/obs_dc<br/>STATUS: BACKUP (standby)"]
    end

    subgraph stby01["stby01"]
        OBSDR["obs_dr<br/>systemd: dgmgrl-observer-obs_dr.service<br/>Wallet: /etc/oracle/wallet/obs_dr<br/>STATUS: BACKUP (standby)"]
    end

    subgraph dbs["Monitored databases"]
        PRIM_DB["PRIM (RAC)<br/>:1522 PRIM_DGMGRL"]
        STBY_DB["STBY<br/>:1522 STBY_DGMGRL"]
    end

    BCFG --- OBSEXT
    BCFG --- OBSDC
    BCFG --- OBSDR

    OBSEXT -- "ping ~3s" --> PRIM_DB
    OBSEXT -- "ping ~3s" --> STBY_DB
    OBSDC -. "heartbeat" .- OBSEXT
    OBSDR -. "heartbeat" .- OBSEXT

    OBSDC -. "promote at obs_ext failure<br/>(~30s)" .- BCFG
    OBSDR -. "promote at obs_ext failure<br/>(~30s)" .- BCFG

    classDef master fill:#a5d6a7,stroke:#2e7d32,color:#000
    classDef backup fill:#fff59d,stroke:#f9a825,color:#000
    classDef cfg fill:#ce93d8,stroke:#6a1b9a,color:#000
    classDef dbnode fill:#90caf9,stroke:#1565c0,color:#000

    class OBSEXT master
    class OBSDC,OBSDR backup
    class BCFG cfg
    class PRIM_DB,STBY_DB dbnode
```

> 💡 **Promote Backup → Master:** after the Master Observer fails, one of the Backups automatically takes over the active role within 10–60 s (depending on Threshold). FSFO remains `ENABLED` throughout that window.
> 💡 **Each Observer has its own wallet** — `mkstore` with the SYS password for `PRIM_ADMIN`/`STBY_ADMIN` (we do not share wallets across hosts).

---

## 6. TAC + UCP client + FAN events

```mermaid
flowchart TB
    subgraph client["client01 — TestHarness UCP"]
        APP["TestHarness.java<br/>oracle.jdbc.replay.OracleDataSourceImpl"]
        POOL["UCP Pool<br/>min=5 max=20<br/>FastConnectionFailover=true"]
        ONSCONFIG["ONSConfiguration<br/>nodes=prim01:6200,prim02:6200,stby01:6200"]
    end

    subgraph srv_prim["RAC Cluster Services"]
        SVC_PRIM["MYAPP_TAC<br/>-pdb APPPDB<br/>-failovertype TRANSACTION<br/>-failover_restore LEVEL1<br/>-commit_outcome TRUE<br/>-session_state DYNAMIC<br/>-role PRIMARY"]
        ONS_PRIM["ONS daemon<br/>:6200 (CRS resource)"]
    end

    subgraph srv_stby["Oracle Restart Services (stby01)"]
        SVC_STBY["MYAPP_TAC<br/>-pdb APPPDB<br/>-role PRIMARY<br/>(config-only - activates after failover)"]
        ONS_STBY["ONS daemon<br/>:6200<br/>systemd oracle-ons.service"]
    end

    subgraph tg["Transaction Guard (server-side)"]
        LTXID["LTXID tablespace<br/>commit_outcome tracking"]
        REPLAY["Replay context<br/>GV$REPLAY_CONTEXT"]
    end

    APP --> POOL
    POOL -- "JDBC URL<br/>@MYAPP_TAC" --> SVC_PRIM
    POOL -. "after failover" .-> SVC_STBY
    POOL <-->|"FAN events<br/>UP/DOWN/PLANNED"| ONS_PRIM
    POOL <-->|"FAN events<br/>cross-site"| ONS_STBY

    SVC_PRIM --- LTXID
    SVC_PRIM --- REPLAY
    SVC_STBY --- LTXID

    classDef cli fill:#f3e5f5,stroke:#7b1fa2,color:#000
    classDef rac fill:#c8e6c9,stroke:#388e3c,color:#000
    classDef restart fill:#fff9c4,stroke:#f57f17,color:#000
    classDef tgnode fill:#ffe0b2,stroke:#e65100,color:#000

    class APP,POOL,ONSCONFIG cli
    class SVC_PRIM,ONS_PRIM rac
    class SVC_STBY,ONS_STBY restart
    class LTXID,REPLAY tgnode
```

**What this configuration provides:**
- **`failovertype=TRANSACTION`** — saves the session context + LTXID before each call
- **`failover_restore=LEVEL1`** — replay from the last committed point (NOT from the start of the session)
- **`commit_outcome=TRUE`** — Transaction Guard knows what was committed
- **FAN events over ONS** — the client is notified about service role changes immediately (push, not poll)
- **Cross-site ONS** — `mesh nodes=prim01:6200,prim02:6200,stby01:6200` provides notifications from both sides of the architecture

---

## 7. Sequence: unplanned failover (FSFO)

```mermaid
sequenceDiagram
    autonumber
    participant App as TestHarness<br/>(client01)
    participant ONS as ONS Mesh<br/>(prim01/02 + stby01)
    participant Obs as Master Observer<br/>(infra01 obs_ext)
    participant Prim as RAC Primary<br/>(prim01 + prim02)
    participant Stby as STBY<br/>(Active DG)
    participant Brk as DG Broker

    Note over App,Stby: T+0s — Steady state, FSFO ENABLED
    App->>Prim: INSERT INTO test_log...<br/>(LTXID recorded)
    Prim->>Stby: Redo SYNC (AFFIRM)
    Prim->>App: COMMIT OK

    Note over App,Stby: T+1s — Primary failure (kill -9 SMON)
    Prim-xObs: no heartbeat
    App-xPrim: ORA-03113

    Note over Obs: T+1..30s — Threshold timer
    Obs->>Prim: ping #1 (fail)
    Obs->>Prim: ping #2 (fail)
    Obs->>Prim: ping #3 (fail)

    Note over Obs,Brk: T+30s — Threshold reached
    Obs->>Brk: initiate failover
    Brk->>Stby: FAILOVER (broker)
    Stby->>Stby: STARTUP UPGRADE → OPEN<br/>role=PRIMARY

    Note over Stby: T+35s — Oracle Restart auto-start MYAPP_TAC<br/>(registered with -role PRIMARY)
    Stby->>ONS: service UP event
    ONS->>App: FAN: service moved to STBY

    Note over App: T+35..45s — UCP replay
    App->>App: SQLRecoverableException
    App->>Stby: new session via @MYAPP_TAC
    Stby-->>App: Application Continuity replays<br/>uncommitted statements
    App->>Stby: continue INSERT...
    Stby->>App: COMMIT OK

    Note over App,Stby: T+45s — RTO ≈ 30-45s, RPO=0 (ZDL)
```

---

## 8. Sequence: planned switchover

```mermaid
sequenceDiagram
    autonumber
    participant Op as Operator<br/>(infra01)
    participant Brk as DG Broker
    participant App as TestHarness
    participant Prim as RAC PRIM
    participant Stby as STBY
    participant CRS as Oracle Restart<br/>(stby01)

    Note over Op,Stby: T+0s — Switchover PRIM → STBY
    Op->>Brk: VALIDATE DATABASE STBY
    Brk-->>Op: Ready for Switchover: Yes
    Op->>Brk: SWITCHOVER TO STBY

    Brk->>Prim: drain MYAPP_TAC (drain_timeout=300s)
    Prim->>App: signal drain (FAN PLANNED DOWN)
    App->>App: complete current tx, return to pool

    Brk->>Prim: convert to PHYSICAL_STANDBY
    Prim->>Prim: open MOUNT (standby)

    Brk->>Stby: convert to PRIMARY
    Stby->>Stby: ALTER DATABASE COMMIT TO SWITCHOVER<br/>STARTUP → OPEN
    Stby->>CRS: trigger service start (-role PRIMARY)
    CRS->>Stby: srvctl start service MYAPP_TAC

    Stby->>App: FAN UP (via ONS mesh)
    App->>Stby: new connections via @MYAPP_TAC

    Note over App: ~5–15s — no transaction loss,<br/>UCP resumes without errors

    Note over Op: optional SWITCHOVER TO PRIM
    Op->>Brk: SWITCHOVER TO PRIM
    Brk->>Stby: drain → PHYSICAL_STANDBY<br/>(Active DG SAVE STATE → auto OPEN RO)
    Brk->>Prim: PRIMARY → OPEN
    Note over App,Prim: back on RAC
```

---

## 9. Security: wallets and passwords

```mermaid
flowchart TB
    subgraph secrets["Source secrets"]
        SECFILE["/root/.lab_secrets<br/>chmod 600<br/>export LAB_PASS=...<br/><br/>(one file on each host<br/>that runs the bash scripts)"]
    end

    subgraph w_infra["infra01"]
        WEXT["/etc/oracle/wallet/obs_ext<br/>cwallet.sso (auto-login)<br/>credentials:<br/>- PRIM_ADMIN sys<br/>- STBY_ADMIN sys"]
    end

    subgraph w_prim01["prim01"]
        WDC["/etc/oracle/wallet/obs_dc<br/>cwallet.sso<br/>analogous to obs_ext"]
        WBROKER["~/wallet/dgmgrl_prim<br/>create_standby_broker.sh<br/>credential PRIM sys"]
    end

    subgraph w_stby01["stby01"]
        WDR["/etc/oracle/wallet/obs_dr<br/>cwallet.sso<br/>analogous"]
    end

    subgraph w_client["client01"]
        ENV["env: APP_PASSWORD<br/>(optional)<br/>fallback in TestHarness:<br/>Oracle26ai_LAB!"]
    end

    SECFILE -- "sourced in scripts<br/>(ssh_setup, setup_observer,<br/>create_standby_broker)" --> WEXT
    SECFILE --> WDC
    SECFILE --> WDR
    SECFILE --> WBROKER

    WEXT -- "/@PRIM_ADMIN<br/>(no password in CLI)" --> DGMGRL_PRIM["DGMGRL → PRIM:1522"]
    WEXT -- "/@STBY_ADMIN" --> DGMGRL_STBY["DGMGRL → STBY:1522"]
    WDC -- "/@PRIM_ADMIN" --> DGMGRL_PRIM
    WDR -- "/@STBY_ADMIN" --> DGMGRL_STBY

    classDef src fill:#ffcdd2,stroke:#c62828,color:#000
    classDef wallet fill:#dcedc8,stroke:#558b2f,color:#000
    classDef target fill:#bbdefb,stroke:#1565c0,color:#000

    class SECFILE src
    class WEXT,WDC,WDR,WBROKER,ENV wallet
    class DGMGRL_PRIM,DGMGRL_STBY target
```

**Lab password convention (see `01_Architektura` section 2):**
- All OS accounts (root, oracle, grid, kris) and DB accounts (SYS, SYSTEM, ASM, PDB Admin, app_user): `Oracle26ai_LAB!`
- `LAB_PASS` in `/root/.lab_secrets` — read by every bash script (`source` at the top)
- `APP_PASSWORD` in TestHarness — env var with fallback to the hardcoded lab default

In production, each of these wallets has a separate password from a secret store (HashiCorp Vault / Oracle Wallet with Master Key); environment variables are not embedded in code or in the repo.

---

## 10. Network port matrix (firewall)

```mermaid
flowchart LR
    subgraph clients["Client side"]
        CL[client01]
        OBS[Observer hosts<br/>infra01/prim01/stby01]
    end

    subgraph servers["Server side"]
        PRIM01[prim01]
        PRIM02[prim02]
        STBY[stby01<br/>Oracle Restart]
        INFRA[infra01<br/>Infra services]
    end

    CL -- "1521/tcp<br/>SQL Net listener" --> PRIM01
    CL -- "1521/tcp" --> PRIM02
    CL -- "1521/tcp" --> STBY
    OBS -- "1522/tcp<br/>DGMGRL listener" --> PRIM01
    OBS -- "1522/tcp<br/>DGMGRL listener" --> PRIM02
    OBS -- "1522/tcp<br/>DGMGRL listener" --> STBY

    PRIM01 -- "6200/tcp ONS<br/>cross-site FAN" --> STBY
    PRIM02 -- "6200/tcp ONS" --> STBY
    STBY -- "6200/tcp ONS" --> PRIM01
    STBY -- "6200/tcp ONS" --> PRIM02
    CL -- "6200/tcp<br/>ONS subscribe" --> PRIM01
    CL -- "6200/tcp ONS" --> STBY

    PRIM01 <-->|"27015/tcp CRS<br/>42424/tcp+udp interconnect<br/>(NIC enp0s8 trust)"| PRIM02

    PRIM01 -- "3260/tcp iSCSI<br/>NIC enp0s9 MTU 9000" --> INFRA
    PRIM02 -- "3260/tcp iSCSI" --> INFRA

    CL -- "53/udp+tcp<br/>DNS lab.local" --> INFRA
    CL -- "123/udp NTP" --> INFRA

    classDef cli fill:#f3e5f5,stroke:#7b1fa2,color:#000
    classDef srv fill:#c8e6c9,stroke:#388e3c,color:#000

    class CL,OBS cli
    class PRIM01,PRIM02,STBY,INFRA srv
```

**Port table:**

| Port | Protocol | Direction | Purpose | Configured in |
|------|----------|-----------|---------|---------------|
| 1521 | tcp | client→DB | SQL*Net listener (LREG service registration) | kickstart prim01/02 |
| 1522 | tcp | Observer→DB | DGMGRL listener (broker management, StaticConnectIdentifier) | kickstart prim01/02 |
| 6200 | tcp | client↔server / mesh | ONS / FAN events | kickstart prim01/02 + `oracle-ons.service` on stby01 |
| 27015 | tcp | within cluster | CRS daemon (HAIP) | kickstart prim01/02 |
| 42424 | tcp+udp | within cluster | Cluster interconnect (CSS, DRM) | trust=enp0s8 (full) |
| 3260 | tcp | initiator→target | iSCSI | kickstart infra01 |
| 53 | udp/tcp | client→infra01 | DNS bind9 | kickstart infra01 |
| 123 | udp | client→infra01 | NTP chronyd | kickstart infra01 |

> 💡 **`--trust=enp0s8 --trust=enp0s9` in kickstart prim01/02** opens these interfaces fully (interconnect + storage) — they are internal VirtualBox networks, not reachable from outside the cluster.

---

## Related documents

- `01_Architecture_and_Assumptions.md` — topology details in tabular form
- `03_Storage_iSCSI.md` — iSCSI block backstore implementation
- `04_Grid_Infrastructure.md` — GI Cluster + Oracle Restart installation
- `06_Data_Guard_Standby.md` — DG Broker + Active DG (persistent READ ONLY WITH APPLY)
- `07_FSFO_Observers.md` — Master + 2 Backup Observers
- `08_TAC_and_Tests.md` — TAC service + UCP client
- `09_Test_Scenarios.md` — operational FSFO/TAC tests
- `10_Performance_Tuning.md` — optimizations (paravirt KVM, HugePages, jumbo, write-back)
- `../FIXES_PLAN_v2.md` — full fixes plan from the review

---

**Version:** 1.0 (VMs2-install) | **Date:** 2026-04-27 | **Format:** Mermaid 10.x
