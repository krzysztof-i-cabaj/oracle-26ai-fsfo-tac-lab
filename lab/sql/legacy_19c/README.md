# Legacy 19c — DO NOT RUN

> **Ostrzezenie [PL]:** Pliki w tym katalogu sa **reliktami z iteracji `VMs/`** (instalacja pisana
> pierwotnie pod Oracle 19c). Zostaly tu przeniesione, by mozna bylo siegnac do nich w razie
> potrzeby porownawczej, ale **NIE NALEZY ich uruchamiac na bazie 26ai (23.26.1)**. Akceptuja
> banner `LIKE '%19.%'` jako PASS i moga zwrocic falszywie pozytywne wyniki readiness/walidacji.
>
> **Warning [EN]:** Files in this directory are **legacy artifacts from the `VMs/` iteration**
> (originally written for Oracle 19c). They were moved here for diff/comparison reference only —
> **DO NOT RUN against 26ai (23.26.1)**. They accept `LIKE '%19.%'` banners as PASS and may
> produce false-positive readiness/validation results.

## Pliki / Files

| Plik / File | Aktualna wersja 26ai / Current 26ai version |
|-------------|----------------------------------------------|
| `validate_environment.sql` | `../validate_environment_26ai.sql` |
| `tac_full_readiness.sql` | `../tac_full_readiness_26ai.sql` |
| `tac_replay_monitor.sql` | `../tac_replay_monitor_26ai.sql` |
| `fsfo_check_readiness.sql` | (w `../fsfo_*` — sprawdz tac/fsfo readiness 26ai) |
| `fsfo_monitor.sql` | `../fsfo_monitor_26ai.sql` |

## Powod migracji / Rationale

Refaktoryzacja `VMs2-install` (zob. `../../FIXES_19c_to_26ai.md` i `../../FIXES_PLAN_v2.md`
F-05) usuwa zaszlosci 19c: `dba_services` → `cdb_services`, `GV$REPLAY_STAT_SUMMARY` →
`GV$REPLAY_CONTEXT`, `commit_outcome='TRUE'` → `'YES'`, banner check `LIKE '%23.%'/'%26.%'` only.

W razie chęci porównania starej i nowej wersji uzyj `diff -u legacy_19c/foo.sql ../foo_26ai.sql`.
