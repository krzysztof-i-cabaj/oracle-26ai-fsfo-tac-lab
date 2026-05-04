# ⚙️ SETTINGS — parametry per projekt

[![Doc](https://img.shields.io/badge/Doc-Settings-blueviolet)]()
[![Scope](https://img.shields.io/badge/Scope-ZDLRA__like-blue)]()
[![Globalne](https://img.shields.io/badge/Globalne-~%2F.claude%2FCLAUDE.md-orange)]()
[![Lang](https://img.shields.io/badge/Lang-PL_+_EN-blue)](SETTINGS.md)

> 🇬🇧 [English version →](SETTINGS.md)

> 🎯 **Tylko to, co project-specific.** Konwencje globalne (nagłówki skryptów, ikony, badge'y, polityka `LAB_PASS`) znajdują się w **`~/.claude/CLAUDE.md`** i nie są tu powtarzane.

---

## 📍 Root projektu: `ZDLRA_like`

Root projektu to katalog `ZDLRA_like/` — top-level folder tego podprojektu. Po publikacji w repo [oracle-26ai-fsfo-tac-lab](https://github.com/krzysztof-i-cabaj/oracle-26ai-fsfo-tac-lab) na GitHub, znajduje się on w roocie repozytorium.

Każdy skrypt i dokument odwołuje się do tego rootu po nazwie `ZDLRA_like`. Każdy plik skryptu deklaruje go w bilingual nagłówku (linia `# <repo>:       ZDLRA_like`) — `<repo>:` to label nagłówka, `ZDLRA_like` to wartość.

> 📝 **Uwaga:** placeholder `<repo>` był wcześniej używany jako relokowalny token; został zamieniony na konkretną nazwę `ZDLRA_like` dla czytelności (projekt jest teraz stabilny). Label nagłówka `<repo>:` pozostał jako konwencja zdefiniowana w `~/.claude/CLAUDE.md`.

---

## 📦 Kopiowanie plików na Linuxa

Wzorzec globalny: `scp ZDLRA_like/<dir>/<file> root@<host>:/tmp/<dir>/<file>`

Konkretne przykłady dla tego projektu:

```bash
# Sprint 0 — boot automation (działa z hosta Windows, nic na Linux)

# Sprint 1 — instalacja rcat01
scp ZDLRA_like/scripts/setup_oracle_env_rcat.sh         root@rcat01:/tmp/scripts/
scp ZDLRA_like/scripts/install_db_silent_rcat.sh        oracle@rcat01:/tmp/scripts/
scp ZDLRA_like/scripts/dbca_create_rcat.sh              oracle@rcat01:/tmp/scripts/
scp ZDLRA_like/scripts/setup_systemd_oracle_unit.sh     root@rcat01:/tmp/scripts/
scp ZDLRA_like/scripts/systemd/oracle-rcat.service      root@rcat01:/tmp/scripts/systemd/
scp ZDLRA_like/scripts/catalog_create.sh                oracle@rcat01:/tmp/scripts/
scp ZDLRA_like/scripts/catalog_register_prim.sh         oracle@rcat01:/tmp/scripts/
scp ZDLRA_like/response_files/db_rcat_se2.rsp           oracle@rcat01:/tmp/scripts/
scp ZDLRA_like/sql/0[1-3]_*.sql                         oracle@rcat01:/tmp/sql/

# DNS na infra01
scp ZDLRA_like/scripts/setup_dns_rcat_on_infra01.sh     root@infra01:/tmp/

# Sprint 2/3 — backup + ZDLRA-like (wykonywane z prim01)
scp ZDLRA_like/scripts/rman_*.sh ZDLRA_like/scripts/zdlra_sim_setup.sh  oracle@prim01:/tmp/scripts/
scp ZDLRA_like/sql/[12]?_*.sql                                          oracle@prim01:/tmp/sql/

# Bulk wszystko na rcat01 (Sprint 1):
scp -r ZDLRA_like/scripts/* ZDLRA_like/sql/* ZDLRA_like/response_files/* root@rcat01:/tmp/
```

---

## 🔐 Hasło LAB (`/root/.lab_secrets` + `$LAB_PASS`)

Zunifikowane hasło dla całego LAB-u (również parent FSFO/TAC LAB): **`Oracle26ai_LAB!`**

- **Źródło prawdy:** `ZDLRA_like/kickstart/ks-rcat01.cfg` (linia `rootpw --plaintext`)
- **Dystrybucja:** sekcja `%post` w kickstart automatycznie tworzy `/root/.lab_secrets` (chmod 600, owner root) + `/home/oracle/.lab_secrets` (chmod 600, owner oracle), oba z `export LAB_PASS='Oracle26ai_LAB!'`

### Tworzenie pliku ręcznie (jeśli nie z kickstart)

```bash
sudo tee /root/.lab_secrets >/dev/null <<'EOF'
export LAB_PASS='Oracle26ai_LAB!'
EOF
sudo chmod 600 /root/.lab_secrets
```

### Source w skryptach `.sh`

Każdy skrypt w `ZDLRA_like/scripts/` ma na początku ten blok:

```bash
[ -r /root/.lab_secrets ] && source /root/.lab_secrets
[ -r "$HOME/.lab_secrets" ] && source "$HOME/.lab_secrets"
if [ -z "${LAB_PASS:-}" ]; then
    echo "BŁĄD: LAB_PASS nie ustawiona. Stwórz /root/.lab_secrets (chmod 600)."
    exit 1
fi
```

### Pliki SQL — pozycyjny parametr `&1`

```bash
sqlplus -S sys/${LAB_PASS}@rcat01:1521/RCATPDB as sysdba \
    @ZDLRA_like/sql/01_create_catalog_schema.sql "${LAB_PASS}"
```
```sql
DEFINE rman_pass = "&1"
CREATE USER rman_cat IDENTIFIED BY "&rman_pass" ...
```

W produkcji: Oracle Wallet / JCEKS / Vault — **nigdy** plain text.

---

## 🔗 Mapa plików projektu

| Plik | Rola |
|---|---|
| [`README.md`](README.md) / [`README_PL.md`](README_PL.md) | Przegląd, wymagania, szybki start |
| [`DESIGN.md`](DESIGN.md) / [`DESIGN_PL.md`](DESIGN_PL.md) | ADR-y (6 decyzji), kompatybilność, security, plan iteracji |
| [`SETTINGS.md`](SETTINGS.md) / [`SETTINGS_PL.md`](SETTINGS_PL.md) | Konwencje projektu, ścieżki, secrets policy (ten plik) |
| [`zdlra.html`](zdlra.html) / [`zdlra_PL.html`](zdlra_PL.html) | Landing page z topology SVG |
| [`docs/01_Architecture_PL.md`](docs/01_Architecture_PL.md) | Topologia, hosty/IP, komponenty rcat01, stack MAA |
| [`docs/02_Boot_Automation_PoC_PL.md`](docs/02_Boot_Automation_PoC_PL.md) | Sprint 0 — VBoxManage scancode |
| [`docs/03_VM_Preparation_PL.md`](docs/03_VM_Preparation_PL.md) | Sprint 1 krok 1 — VM + kickstart |
| [`docs/04_DB_Install_and_Auto_Start_PL.md`](docs/04_DB_Install_and_Auto_Start_PL.md) | Sprint 1 krok 2 — DB + DBCA + systemd. **Wszystkie ścieżki ORACLE_HOME, oradata, FRA tutaj.** |
| [`docs/05_Catalog_Setup_PL.md`](docs/05_Catalog_Setup_PL.md) | Sprint 1 krok 3 — schemat rman_cat. **DB identifiers (CDB/PDB/schema/TNS) tutaj.** |
| [`docs/06_Backup_Policy_PL.md`](docs/06_Backup_Policy_PL.md) | Sprint 2 — **polityka backupowa** (cykle, retention, cron) |
| [`docs/07_ZDLRA_Like_Simulation_PL.md`](docs/07_ZDLRA_Like_Simulation_PL.md) | Sprint 3 — real-time redo + virtual full |
| [`docs/08_Backup_Restore_Scenarios_PL.md`](docs/08_Backup_Restore_Scenarios_PL.md) | 8 scenariuszy testowych B-1..B-8 |
| [`docs/09_DG_Integration_PL.md`](docs/09_DG_Integration_PL.md) | Backup ↔ Data Guard |
| [`docs/10_Troubleshooting_PL.md`](docs/10_Troubleshooting_PL.md) | FAQ + znane błędy + kumulatywne lekcje #1-#34 |
| [`docs/architecture.svg`](docs/architecture.svg) | Standalone diagram topologii (PRIM RAC + STBY + rcat01) |
| [`zdlra-backup-live-test/`](zdlra-backup-live-test/) | 🔴 **Killer demo** — log autonomicznej sesji testowej agenta AI |

**Parent project:** [oracle-26ai-fsfo-tac-lab on GitHub](https://github.com/krzysztof-i-cabaj/oracle-26ai-fsfo-tac-lab) (LAB Oracle 26ai HA MAA — FSFO/TAC)
