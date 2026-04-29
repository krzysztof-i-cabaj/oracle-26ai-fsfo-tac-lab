> 🇬🇧 English | [🇵🇱 Polski](./README_PL.md)

# 📚 Legacy — Lessons Learned

> Knowledge base archive from the **first iteration of the environment** (`VMs/`), kept as educational material.
> The production LAB deployment (second iteration, on which this repo is based) lives in [`../../lab/`](../../lab/).

---

## What is here?

### `FIXES_LOG.md`

**294 KB · 5,197 lines · 96 fixes (FIX-001 → FIX-096)**

A chronological log of problems encountered and their solutions during the first iteration of building the Oracle 26ai MAA lab (RAC + Active Data Guard + FSFO + TAC, 5 VMs in VirtualBox).

Each entry follows this format:
- **Problem** — what went wrong
- **Symptom** — what the operator saw (message, error, log)
- **Fix** — how it was resolved
- **Links** to the affected files/sections

---

## Why "legacy"?

The first iteration of the environment (`VMs/` in the original project) was an experimental build — many configuration decisions were revised in the second iteration (`VMs2-install/` → `lab/` in this repo). The scripts, kickstart, and procedures in `lab/` are the result of a from-scratch rewrite based on conclusions drawn from these 96 fixes.

`FIXES_LOG.md` itself was preserved because it documents **counterintuitive Oracle behaviors** that did not change between 19c and 26ai and that will likely show up again for anyone reproducing such an environment.

---

## Most interesting fixes (short index)

| Fix | Topic | Why it is worth reading |
|---|---|---|
| **FIX-004** | Kickstart backslash continuation | Anaconda does not support `\` at the end of a line — the classic "works-only-once" install bug |
| **FIX-076** | FSFO Zero Data Loss = Flashback Database on **both** sides | Auto-Reinstate requires Flashback on both sides of the broker config |
| **FIX-087** | Java 17+ TAC requires `--add-opens` | Proxy generation in UCP needs JVM module access for `java.base/java.lang` |
| **FIX-090** | 26ai vs 19c SQL variants | Where it pays off to split `*_19c.sql` from `*_26ai.sql` (CDB-aware checks) |
| **FIX-095** | TAC service does not auto-start on a non-Grid standby | Oracle Restart requires `srvctl modify pdb -policy AUTOMATIC -role PRIMARY` |

---

## How to use it?

```bash
# Quick structural overview
grep -n "^## " FIXES_LOG.md | head -20

# Search for a specific problem
grep -i -A 3 "ORA-XXXXX" FIXES_LOG.md

# List all 96 fixes
grep -E "^### FIX-[0-9]+" FIXES_LOG.md
```

---

**Status:** Read-only archive. New lessons-learned from current sessions go into [`../../lab/EXECUTION_LOG.md`](../../lab/EXECUTION_LOG.md) (sessions S01–S28 = ~70 fixes S28-1..S28-68).
