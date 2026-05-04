# 🏗️ DESIGN — Recovery Appliance (ZDLRA-like) podprojekt

[![Doc Type](https://img.shields.io/badge/Type-Architecture-blueviolet)]()
[![ADRs](https://img.shields.io/badge/ADRs-6-success)]()
[![Status](https://img.shields.io/badge/Status-Approved-green)]()
[![Sprint](https://img.shields.io/badge/Sprints-0%20%7C%201%20%7C%202%20%7C%203-orange)]()
[![Compat](https://img.shields.io/badge/Oracle-26ai_23.26.1-red)]()
[![OS](https://img.shields.io/badge/OL-8.10-orange)]()

> 📐 Decyzje architektoniczne, kompatybilność, bezpieczeństwo, plan iteracji.
> Architecture decisions, compatibility, security, iteration plan.

## 1. 🎯 Kontekst / Context

[PL] LAB `VMs2-install` pokrywa HA (RAC) + DR (Active DG + FSFO + TAC), ale brakuje warstwy backup.
Domknięcie pełnego MAA stack jest naturalnym rozszerzeniem dydaktycznym. ZDLRA jako commercial appliance
nie da się zainstalować — symulujemy kluczowe funkcje przez plain RMAN + DG redo transport.

[EN] Existing lab covers HA + DR; backup layer is missing. ZDLRA is closed-source hardware appliance,
not installable in VBox — we simulate its key features via plain RMAN + DG redo transport.

## 2. 📋 Decyzje architektoniczne / Architecture Decision Records

### ADR-001: Single Instance + systemd zamiast Oracle Restart

- **Status:** Zatwierdzone / Accepted
- **Data / Date:** 2026-05-01
- **Kontekst [PL]:** rcat01 to mała VM dla katalogu RMAN (4 GB RAM). Grid Infrastructure for Standalone Server
  (Oracle Restart) zapewnia auto-restart instancji po crashu, ale dodaje ~3 GB RAM overhead i drugi binary install.
- **Decyzja [PL]:** Zwykła Single Instance + systemd unit `oracle-rcat.service` wywołujący `dbstart`/`dbshut`.
  Auto-start po reboocie OS jest wystarczający dla tego use-case; pojedyncza VM się rzadko crashuje wewnętrznie.
- **Konsekwencje [PL]:** Mniej RAM, prostsza instalacja, brak Oracle-managed monitoringu instancji.
  Jeśli okaże się że potrzebujemy auto-restart po crashu DB → migracja na Oracle Restart w iteracji v2.
- **Alternatywy odrzucone:** Grid Infrastructure for Standalone Server (zbyt duży overhead);
  prosty `@reboot` w crontab oracle (mniej standardowe niż systemd).

### ADR-002: Podprojekt wyodrębniony jako standalone `ZDLRA_like/` (top-level w repo oracle-26ai-fsfo-tac-lab)

- **Status:** Zatwierdzone / Accepted (zrewidowane 2026-05-04 — ekstrakcja z `VMs2-install/_RecoveryAppliance_/` do standalone repo folderu)
- **Data / Date:** 2026-05-01 (initial) / 2026-05-04 (zrewidowane — ekstrakcja repo)
- **Kontekst [PL]:** Pierwotnie podkatalog **wewnątrz** `VMs2-install/_RecoveryAppliance_/` (część tej samej instalacji LAB-u), ale od początku zaprojektowany jako self-contained. Po ukończeniu Sprintów 0-3 + autonomous test session, podprojekt został wyodrębniony jako **top-level folder `ZDLRA_like/`** w repo [oracle-26ai-fsfo-tac-lab](https://github.com/krzysztof-i-cabaj/oracle-26ai-fsfo-tac-lab) na GitHub dla łatwiejszej referencji i samodzielnego użycia.
- **Decyzja [PL]:** **`ZDLRA_like/` jest rootem projektu.** Self-contained — każdy potrzebny plik (scripts, sql, docs, kickstart, response_files) znajduje się wewnątrz tego folderu; brak runtime dependencies na parent. Parent project (LAB FSFO/TAC) jest referowany tylko dla kontekstu (baza PRIM, SSH equivalency, konwencja `LAB_PASS`).
- **Konsekwencje [PL]:** Lekka duplikacja kodu przeniesiona z oryginalnej ko-lokacji (np. `setup_oracle_env.sh` skopiowany z dostosowaniem). Teraz `ZDLRA_like/` można klonować/używać niezależnie; `VMs2-install/` jest referowany jako conceptual parent (nie filesystem parent).

### ADR-003: ZDLRA-like, nie ZDLRA

- **Status:** Zatwierdzone / Accepted
- **Data / Date:** 2026-05-01
- **Kontekst [PL]:** ZDLRA to closed-source appliance (hardware + RA Software). Nie da się go zainstalować
  w VBoxie. Można jednak symulować kluczowe funkcje (incremental merge, real-time redo, compression).
- **Decyzja [PL]:** Naming wszędzie **„ZDLRA-like simulation"**. W docs jasno zaznaczamy granicę:
  co symulujemy (incremental merge, virtual full, real-time redo), czego NIE (block dedup, tape-out, RA replication).
- **Konsekwencje [PL]:** Edukacyjnie jasne; brak pretendowania do prawdziwego ZDLRA.

### ADR-004: Sprint 0 — VBoxManage keyboardputscancode jako proof-of-concept

- **Status:** Zatwierdzone / Accepted
- **Data / Date:** 2026-05-01
- **Kontekst [PL]:** Wszystkie istniejące VM w LAB-ie wymagają ręcznej edycji GRUB (TAB + payload) podczas bootu
  ISO. Recovery Appliance to dobry kandydat na test koncepcji automatyzacji — pojedyncza VM, łatwo zweryfikować.
- **Decyzja [PL]:** Sprint 0 implementuje `Send-VBoxKeystrokes` w PowerShell + orchestrator dla rcat01.
  Jeśli zadziała, schemat trafi do osobnego mini-projektu `_KickstartAutomation_/` dla pozostałych VM.
- **Konsekwencje [PL]:** Pełna automatyzacja bootu rcat01 (zero kliknięć użytkownika). Ryzyko timing/keyboard-layout —
  obsłużone w skrypcie przez retry loop i tabelę scancode'ów US-keyboard.

### ADR-006: Konwencja `/root/.lab_secrets` + `$LAB_PASS`

- **Status:** Zatwierdzone / Accepted
- **Data / Date:** 2026-05-01
- **Kontekst [PL]:** Skrypty wstępnej wersji miały hardkodowane `Oracle26ai_LAB!` w wielu miejscach.
  W parent projekcie `VMs2-install/` istnieje już konwencja `/root/.lab_secrets` z `export LAB_PASS=...`,
  używana przez `create_standby_broker.sh`, `setup_observer.sh` itd.
- **Decyzja [PL]:** Recovery Appliance trzyma się tej samej konwencji:
  - kickstart `ks-rcat01.cfg` w `%post` tworzy `/root/.lab_secrets` (chmod 600) + `/home/oracle/.lab_secrets`
  - wszystkie skrypty `.sh` zaczynają od bloku source + walidacji `$LAB_PASS`
  - SQL `01_create_catalog_schema.sql` przyjmuje hasło jako pozycyjny `&1`, wywołanie z bash przekazuje `${LAB_PASS}`
  - PowerShell Write-Host info wskazuje `/root/.lab_secrets` zamiast wprost hasła
- **Konsekwencje [PL]:** Spójność z parent projektem. Łatwa rotacja hasła (jeden plik). Brak hardkodów w git.
- **Alternatywy odrzucone:** hardcode w skryptach (nie-secure); env var w cron (cron nie ma terminala);
  mkstore/wallet (overkill na LAB).

### ADR-005: Backup target lokalny + vboxsf shared folder

- **Status:** Zatwierdzone / Accepted
- **Data / Date:** 2026-05-01
- **Kontekst [PL]:** `/mnt/rman_bck` jest już zmontowany jako vboxsf na infra01/prim01/prim02/stby01 i wskazuje
  na shared folder hosta Windows. To pozwala na backupy wykonywane z PRIM bezpośrednio na ten katalog.
- **Decyzja [PL]:** Backupy fizyczne piszemy do `/mnt/rman_bck/` (host shared folder), katalog metadanych
  RMAN w PDB `RCATPDB` na rcat01. Lokalny dysk 200 GB rcat01 trzyma katalog DB + FRA + cache archivelog.
- **Konsekwencje [PL]:** Backupy przeżyją zniszczenie wszystkich VM (są na hoście Windows). Performance vboxsf
  jest niższy niż natywny dysk — akceptowalne dla LAB-u.

## 3. 🔌 Kompatybilność / Compatibility

| Komponent | Wersja | Uwagi [PL] |
|---|---|---|
| Oracle Database | 26ai 23.26.1 SE2/EE | Spójne z PRIM/STBY |
| Oracle Linux | 8.10 | Ten sam ISO co reszta |
| Linux kernel | UEK7 (default OL 8.10) | Wspierany przez 23ai preinstall RPM |
| RMAN catalog DB version | 26ai (23.26.1) | Musi być >= wersja TARGET DB (PRIM = 23.26.1) — OK |
| VirtualBox | 7.x | Linia poleceń `VBoxManage` zgodna |
| `keyboardputscancode` | VBox 6.0+ | Stabilne API od wielu lat |

## 4. 🔐 Bezpieczeństwo / Security

- **Hasła** — konwencja **`$LAB_PASS` z `/root/.lab_secrets`** (chmod 600), zgodnie z `VMs2-install/scripts/`.
  Plik tworzony automatycznie przez kickstart (`%post`) na rcat01 + kopia w `/home/oracle/.lab_secrets`.
  Wszystkie skrypty `.sh` źródłują secrets na początku i walidują że `$LAB_PASS` nie jest pusty.
  W produkcji: Oracle Wallet / JCEKS / Vault.
- **Połączenia do katalogu** z PRIM: TNS przez listener na rcat01:1521, hasło z `$LAB_PASS`
- **SQL** ze SQL*Plus DEFINE: `01_create_catalog_schema.sql` przyjmuje `$LAB_PASS` jako pozycyjny parametr `&1`
- Brak TDE w pierwszej iteracji (osobny scenariusz w przyszłości)
- Backupy unencrypted w pierwszej iteracji
- `firewall --disabled` na rcat01 (LAB convention)

## 5. 🧪 Testy / Tests

8 scenariuszy w `docs/08_Backup_Restore_Scenarios.md`:
B-1 (basic catalog), B-2 (weekly cycle), B-3 (incremental merge),
B-4 (PITR po DROP), B-5 (tablespace recovery), B-6 (controlfile loss),
B-7 (DG rebuild from backup), B-8 (DUPLICATE for test env).

## 6. 🚀 Plan iteracji / Iteration plan

| Sprint | Zakres | Effort |
|---|---|---|
| 0 | Boot automation PoC (keyboardputscancode) | ~0.5 dnia |
| 1 | VM `rcat01` + DB + katalog + auto-start | ~1 dzień |
| 2 | Polityka backupowa + scenariusze B-1, B-2, B-4, B-5, B-6 | ~1 dzień |
| 3 | ZDLRA-like simulation + scenariusze B-3, B-7, B-8 | ~1.5 dnia |
