# ⚙️ SETTINGS — project-specific parameters

[![Doc](https://img.shields.io/badge/Doc-Settings-blueviolet)]()
[![Scope](https://img.shields.io/badge/Scope-ZDLRA__like-blue)]()
[![Globals](https://img.shields.io/badge/Globals-~%2F.claude%2FCLAUDE.md-orange)]()
[![Lang](https://img.shields.io/badge/Lang-EN_+_PL-blue)](SETTINGS_PL.md)

> 🇵🇱 [Polska wersja →](SETTINGS_PL.md)

> 🎯 **Project-specific only.** Global conventions (script headers, icons, badges, `LAB_PASS` policy) live in **`~/.claude/CLAUDE.md`** and are not repeated here.

---

## 📍 Project root: `ZDLRA_like`

The project root is the directory `ZDLRA_like/` — the top-level folder of this subproject. After publication in [oracle-26ai-fsfo-tac-lab](https://github.com/krzysztof-i-cabaj/oracle-26ai-fsfo-tac-lab) GitHub repo, it sits at the repository root.

Every script and document references this root by name `ZDLRA_like`. Each script file declares it in the bilingual header (`# <repo>:       ZDLRA_like` line) — `<repo>:` is the header label, `ZDLRA_like` is the value.

> 📝 **Note:** the placeholder `<repo>` was previously used as a relocatable token; it has been replaced with the concrete name `ZDLRA_like` for clarity (the project is now stable). The header label `<repo>:` is preserved as a convention defined in `~/.claude/CLAUDE.md`.

---

## 📦 Copying files to Linux

Global pattern: `scp ZDLRA_like/<dir>/<file> root@<host>:/tmp/<dir>/<file>`

Concrete examples for this project:

```bash
# Sprint 0 — boot automation (runs from Windows host, nothing on Linux)

# Sprint 1 — install rcat01
scp ZDLRA_like/scripts/setup_oracle_env_rcat.sh         root@rcat01:/tmp/scripts/
scp ZDLRA_like/scripts/install_db_silent_rcat.sh        oracle@rcat01:/tmp/scripts/
scp ZDLRA_like/scripts/dbca_create_rcat.sh              oracle@rcat01:/tmp/scripts/
scp ZDLRA_like/scripts/setup_systemd_oracle_unit.sh     root@rcat01:/tmp/scripts/
scp ZDLRA_like/scripts/systemd/oracle-rcat.service      root@rcat01:/tmp/scripts/systemd/
scp ZDLRA_like/scripts/catalog_create.sh                oracle@rcat01:/tmp/scripts/
scp ZDLRA_like/scripts/catalog_register_prim.sh         oracle@rcat01:/tmp/scripts/
scp ZDLRA_like/response_files/db_rcat_se2.rsp           oracle@rcat01:/tmp/scripts/
scp ZDLRA_like/sql/0[1-3]_*.sql                         oracle@rcat01:/tmp/sql/

# DNS on infra01
scp ZDLRA_like/scripts/setup_dns_rcat_on_infra01.sh     root@infra01:/tmp/

# Sprint 2/3 — backup + ZDLRA-like (executed from prim01)
scp ZDLRA_like/scripts/rman_*.sh ZDLRA_like/scripts/zdlra_sim_setup.sh  oracle@prim01:/tmp/scripts/
scp ZDLRA_like/sql/[12]?_*.sql                                          oracle@prim01:/tmp/sql/

# Bulk everything to rcat01 (Sprint 1):
scp -r ZDLRA_like/scripts/* ZDLRA_like/sql/* ZDLRA_like/response_files/* root@rcat01:/tmp/
```

---

## 🔐 LAB password (`/root/.lab_secrets` + `$LAB_PASS`)

Unified password for the entire LAB (also the parent FSFO/TAC LAB): **`Oracle26ai_LAB!`**

- **Source of truth:** `ZDLRA_like/kickstart/ks-rcat01.cfg` (`rootpw --plaintext` line)
- **Distribution:** the kickstart `%post` section automatically creates `/root/.lab_secrets` (chmod 600, owner root) + `/home/oracle/.lab_secrets` (chmod 600, owner oracle), both with `export LAB_PASS='Oracle26ai_LAB!'`

### Manually creating the file (if not from kickstart)

```bash
sudo tee /root/.lab_secrets >/dev/null <<'EOF'
export LAB_PASS='Oracle26ai_LAB!'
EOF
sudo chmod 600 /root/.lab_secrets
```

### Sourcing in `.sh` scripts

Every script under `ZDLRA_like/scripts/` starts with this block:

```bash
[ -r /root/.lab_secrets ] && source /root/.lab_secrets
[ -r "$HOME/.lab_secrets" ] && source "$HOME/.lab_secrets"
if [ -z "${LAB_PASS:-}" ]; then
    echo "ERROR: LAB_PASS not set. Create /root/.lab_secrets (chmod 600)."
    exit 1
fi
```

### SQL files — positional parameter `&1`

```bash
sqlplus -S sys/${LAB_PASS}@rcat01:1521/RCATPDB as sysdba \
    @ZDLRA_like/sql/01_create_catalog_schema.sql "${LAB_PASS}"
```
```sql
DEFINE rman_pass = "&1"
CREATE USER rman_cat IDENTIFIED BY "&rman_pass" ...
```

In production: Oracle Wallet / JCEKS / Vault — **never** plain text.

---

## 🔗 Map of project files

| File | Role |
|---|---|
| [`README.md`](README.md) / [`README_PL.md`](README_PL.md) | Overview, requirements, quick start |
| [`DESIGN.md`](DESIGN.md) / [`DESIGN_PL.md`](DESIGN_PL.md) | ADRs (6 decisions), compatibility, security, iteration plan |
| [`SETTINGS.md`](SETTINGS.md) / [`SETTINGS_PL.md`](SETTINGS_PL.md) | Project conventions, paths, secrets policy (this file) |
| [`zdlra.html`](zdlra.html) / [`zdlra_PL.html`](zdlra_PL.html) | Landing page with topology SVG |
| [`docs/01_Architecture.md`](docs/01_Architecture.md) | Topology, hosts/IPs, rcat01 components, MAA stack |
| [`docs/02_Boot_Automation_PoC.md`](docs/02_Boot_Automation_PoC.md) | Sprint 0 — VBoxManage scancode |
| [`docs/03_VM_Preparation.md`](docs/03_VM_Preparation.md) | Sprint 1 step 1 — VM + kickstart |
| [`docs/04_DB_Install_and_Auto_Start.md`](docs/04_DB_Install_and_Auto_Start.md) | Sprint 1 step 2 — DB + DBCA + systemd. **All ORACLE_HOME, oradata, FRA paths here.** |
| [`docs/05_Catalog_Setup.md`](docs/05_Catalog_Setup.md) | Sprint 1 step 3 — rman_cat schema. **DB identifiers (CDB/PDB/schema/TNS) here.** |
| [`docs/06_Backup_Policy.md`](docs/06_Backup_Policy.md) | Sprint 2 — **backup policy** (cycles, retention, cron) |
| [`docs/07_ZDLRA_Like_Simulation.md`](docs/07_ZDLRA_Like_Simulation.md) | Sprint 3 — real-time redo + virtual full |
| [`docs/08_Backup_Restore_Scenarios.md`](docs/08_Backup_Restore_Scenarios.md) | 8 test scenarios B-1..B-8 |
| [`docs/09_DG_Integration.md`](docs/09_DG_Integration.md) | Backup ↔ Data Guard |
| [`docs/10_Troubleshooting.md`](docs/10_Troubleshooting.md) | FAQ + known issues + cumulative lessons #1-#34 |
| [`docs/architecture.svg`](docs/architecture.svg) | Standalone topology diagram (PRIM RAC + STBY + rcat01) |
| [`zdlra-backup-live-test/`](zdlra-backup-live-test/) | 🔴 **Killer demo** — autonomous AI agent test session log |

**Parent project:** [oracle-26ai-fsfo-tac-lab on GitHub](https://github.com/krzysztof-i-cabaj/oracle-26ai-fsfo-tac-lab) (Oracle 26ai HA MAA LAB — FSFO/TAC)
