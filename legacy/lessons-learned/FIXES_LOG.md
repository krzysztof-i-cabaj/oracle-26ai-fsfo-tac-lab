> 🇬🇧 English | [🇵🇱 Polski (full 294 KB log)](./FIXES_LOG_PL.md)

# Fixes Log — Index of 96 Historical Fixes (English)

> This is an **English index** to a 294 KB Polish file with **96 detailed fixes** (FIX-001..FIX-096) from the first iteration of the Oracle 26ai MAA lab.
> The full content lives in [FIXES_LOG_PL.md](./FIXES_LOG_PL.md).

## Why this file exists

The first iteration of the lab uncovered ~96 counter-intuitive Oracle behaviors, missing kickstart settings, broker quirks, response-file schema breakage between 19c and 23ai/26ai, and Java UCP / TAC edge cases. Each one was documented in Polish with: problem statement, symptom (often verbatim error output), root cause, fix (diff or command), verification command, and a "Lekcja" (lesson) section generalizing the takeaway.

Translating all 5197 lines was deemed lower-value than preserving the original transcript verbatim and providing this English index — the fix entries are self-contained forensic notes, the error messages and code blocks are universal, and the surrounding Polish narrative is reasonably easy to skim with machine translation when a specific FIX is needed.

## Category breakdown

Approximate distribution (based on a sampling of FIX entries across the file — the boundaries are fuzzy, several fixes touch multiple layers):

| Category | Approx. count | Description |
|----------|---------------|-------------|
| VirtualBox / host bring-up | ~5 | `VBoxManage` host-only adapter naming (Windows vs Linux), shared folders, paravirt clock |
| Kickstart / OS install | ~10 | Anaconda kickstart parser (no `\` continuation, no `--ipv4-dns-search`), `compat-openssl11` not on DVD ISO, `inst.ip` boot params, partitioning, SELinux / firewalld |
| Networking / firewall | ~6 | DNS bind9, chrony NTP roles, ONS port 6200, iSCSI multipath, `scan-prim` resolution, NetworkManager-wait-online |
| Shared storage / iSCSI | ~5 | `iscsi.service` is fire-and-forget oneshot, `After=network-online.target` override, ASM disk discovery, time drift kernel panic on iSCSI I/O storms |
| Grid Infrastructure | ~7 | `gridSetup.sh` silent install, `root.sh` strict sequencing across RAC nodes, `cluvfy`, ASM disk groups, listener auto-start as CRS resource |
| Database creation (DBCA) | ~6 | Silent CDB creation, `dbca_*.rsp` 23.0.0 schema strictness (`asmSysPassword`, `recoveryAreaSize` removed), `recoveryAreaSize` consistency, SRL count math for RAC threads |
| RMAN / DUPLICATE | ~5 | `RMAN DUPLICATE FOR STANDBY`, backup destinations, password file propagation, retention |
| Data Guard transport / config | ~8 | `log_archive_dest_2` automation, AFFIRM verification, broker config file (single per database, not per instance on RAC), `standby_file_management=AUTO`, ORL/SRL recreate on standby, `WHENEVER SQLERROR EXIT FAILURE` killing scripts post-change |
| Data Guard broker | ~10 | `configure_broker.sh` multi-version evolution (v1 → v3), `StaticConnectIdentifier` per-instance on RAC (broker auto-derive picks PORT=1521 wrongly), Threshold vs LagLimit semantics, broker file location on RAC vs SI, ORA-16606/16582/16664 |
| FSFO / Observer | ~8 | Multi-Observer quorum, Oracle Wallet auto-login, `setup_observer_infra01.sh` v1.0 → v1.4, `MaxAvailability` protection mode, ALLOW_HOST override for backup observers, systemd integration, pre-flight Configuration Status SUCCESS gate |
| TAC / Java UCP | ~8 | `failover_type=TRANSACTION`, `-failover_restore LEVEL1`, `ojdbc11.jar` version, FAN events, ONS daemon on SI standby (no Grid), service auto-start on non-Grid promote (FIX-095), `MYAPP_TAC` lowercase / no db_domain in `DBMS_SERVICE.START_SERVICE` |
| Response files (19c → 23ai/26ai) | ~5 | `DECLINE_SECURITY_UPDATES` rejected by 23.0.0 schema (INS-10105), `asmSysPassword` removed, `recoveryAreaSize` moved to `initParams`, allowed-key audit pattern |
| Scripts / automation hardening | ~10 | Bilingual headers, dry-run pattern, idempotency, pre-flight enforcement without cross-user sudo, `PWD` colliding with bash builtin, heredoc password injection, `WHENEVER SQLERROR CONTINUE` for verify queries, sysctl tolerance for VM kernel panics |
| Documentation gaps / structural | ~5 | Script orphans (no doc cross-link), missing UID/GID consistency between architecture doc / kickstart / OS prep, MAA knowledge gaps (SRL math, AFFIRM, broker config file, Threshold/LagLimit, root.sh sequencing) |
| Test scenarios / pre-flight | ~3 | `validate_env.sh` PRIM and STBY parity, `ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY` missing on standby (CDB OPEN ≠ PDB OPEN in 23ai/26ai), `SAVE STATE` illegal on standby (read-only dictionary) |

## Top-cited fixes from this log (referenced elsewhere in the repo)

A handful of fixes are cross-referenced from `lab/README.md`, `lab/OPERATIONS.md`, and `lab/docs/0X_*.md`:

- **FIX-032** — `iscsi.service` `After=network-online.target` + `Restart=on-failure` override (cold-restart reliability of ASM/CRS)
- **FIX-033** — `kernel.softlockup_panic=0` + `watchdog_thresh=30` sysctl tolerance for VirtualBox time drift during heavy I/O
- **FIX-050** — `LISTENER_DGMGRL` on port 1522 (separate from default LISTENER:1521) — referenced by FIX-096 and broker docs
- **FIX-070** — `DECLINE_SECURITY_UPDATES` removal in 23.0.0 client response schema (template for legacy-key audit pattern)
- **FIX-078 / FIX-079** — Listener auto-start as CRS resource on RAC + systemd unit on SI standby; pre-flight enforcement in `configure_broker.sh` v2.10
- **FIX-094** — `ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY` after standby OPEN (CDB OPEN does not auto-open PDBs in 23ai/26ai)
- **FIX-095** — `MYAPP_TAC` service does not auto-start on non-Grid standby after switchover (asymmetric RAC primary + SI standby MAA)
- **FIX-096** — `StaticConnectIdentifier` must be set explicit per-instance on RAC; broker auto-derive picks PORT=1521 from `local_listener` and breaks the second switchover

For other cross-references, search the lab docs for `FIX-NNN` patterns or grep the PL file directly (see below).

## How to navigate the Polish file

```bash
# Find a specific FIX number with surrounding context
grep -A 30 "^### FIX-042" FIXES_LOG_PL.md

# List all titles
grep "^### FIX-" FIXES_LOG_PL.md

# Search by keyword (e.g. "kickstart", "broker", "TAC", "ojdbc")
grep -B 2 -A 10 "kickstart" FIXES_LOG_PL.md

# Jump to a date section
grep -n "^## 2026-04-" FIXES_LOG_PL.md
```

The file is chronologically ordered by date (`## YYYY-MM-DD` headings), with each fix as `### FIX-NNN — <Polish title>`. Each entry contains some mix of: **Problem**, **Objaw** (symptom — usually verbatim error output, language-neutral), **Diagnoza** (diagnosis), **Poprawka** (fix — usually a code/config diff, language-neutral), **Recovery** (rollback or recovery commands), and **Lekcja** (lesson — generalized takeaway).

For an English reader: code blocks, error messages, file paths, and command lines are universal. The Polish narrative around them describes the *reasoning* — paste it into a translator if you need the full story, otherwise the symptom + fix is usually enough.

## Translation policy

This file follows the bilingual repo convention: large historical archives stay in their original language with `_PL` suffix, paired with an English index. The reasoning: translating 5197 lines of forensic detail would multiply the repo size without proportional analytical gain, and the categorical breakdown above is sufficient for an English reader to know whether to dive deeper into a specific FIX number.

The lab's *active* documentation (`lab/README.md`, `lab/docs/index.html`, `lab/OPERATIONS.md`, `concept/docs/*.md`) is being translated to English in full — see the top-level `README.md` for the bilingual file map.
