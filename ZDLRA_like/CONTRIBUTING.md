# 🤝 Contributing to ZDLRA_like

> 🇵🇱 Wkład w projekt — instrukcje poniżej w obu wersjach językowych (EN/PL).

Thank you for your interest! This is an educational LAB project that demonstrates a Recovery Appliance / ZDLRA-Like backup layer for an Oracle 26ai HA MAA setup. Contributions are welcome — bug reports, doc improvements, and additional test scenarios.

Dziękuję za zainteresowanie! To edukacyjny projekt LAB demonstrujący warstwę backup Recovery Appliance / ZDLRA-Like dla Oracle 26ai HA MAA. Wkład jest mile widziany — bug reporty, ulepszenia dokumentacji, dodatkowe scenariusze testowe.

---

## 🐛 Reporting issues / Zgłaszanie błędów

When opening an issue, please include:

- Oracle version (`SELECT * FROM v$version;`)
- OS version (`cat /etc/oracle-release`)
- Which sprint / scenario / lesson failed
- Full error message (RMAN-, ORA-, OS errors)
- Output of `tail -100 alert_*.log` if relevant
- Steps to reproduce

Otwierając zgłoszenie, podaj:

- Wersję Oracle (`SELECT * FROM v$version;`)
- Wersję OS (`cat /etc/oracle-release`)
- Który sprint / scenariusz / lekcja się nie powiodła
- Pełny komunikat błędu (RMAN-, ORA-, OS errors)
- Output `tail -100 alert_*.log` jeśli adekwatny
- Kroki reprodukcji

---

## 📝 Pull requests

### Conventions / Konwencje

- **Bilingual content** — every `.md` file should have both `*.md` (EN) and `*_PL.md` (PL) versions. When updating one, update the other.
- **Script headers** — all `.sh` / `.ps1` / `.sql` / `.cfg` / `.rsp` scripts use the bilingual header format defined in [SETTINGS.md](SETTINGS.md). New scripts must follow it.
- **UTF-8 (no BOM)** — all text files. Polish characters (`ą ć ę ł ń ó ś ź ż` and uppercase) must be preserved. Do NOT use PowerShell 5.1 with `Get-Content -Raw` / `Set-Content -Encoding UTF8` on these files (it corrupts UTF-8 to CP1250). Prefer Python / PowerShell 7+ for bulk edits.
- **Comments**: RMAN scripts use `#` (not `--`). SQL files use `--` for line comments. (Lesson #20.)
- **Naming**: filenames in English. Documentation (markdown) bilingual, comments in scripts also bilingual where relevant.

### Lessons learned

If you discover a new gotcha that isn't in [docs/10_Troubleshooting.md](docs/10_Troubleshooting.md), please add it as the next numbered lesson (currently up to #34). Format:

- Symptom (the error or unexpected behavior)
- Cause (root cause analysis)
- Fix (the working solution)
- Affected files / scripts (if any)

Jeśli odkryjesz nowy gotcha którego nie ma w [docs/10_Troubleshooting_PL.md](docs/10_Troubleshooting_PL.md), dodaj go jako kolejną numerowaną lekcję.

---

## 🧪 Testing / Testowanie

This project's test environment is a 4-VM VirtualBox LAB:

- `prim01` + `prim02` — RAC primary
- `stby01` — physical standby
- `rcat01` — RMAN catalog (this subproject)
- `infra01` — DNS + iSCSI + observer

Before submitting a PR with a behavioral change:

1. Validate locally on the LAB
2. Run at least the affected sprint scripts end-to-end
3. Add a brief reproduction note in the PR description
4. Update [zdlra-backup-live-test/README.md](zdlra-backup-live-test/README.md) if the autonomous test session is affected

---

## 📞 Contact / Kontakt

Author: **KCB Kris** — krzysztof.i.cabaj@gmail.com

LinkedIn: [krzysztof-cabaj](https://www.linkedin.com/in/krzysztof-cabaj-16b6a52)

GitHub Issues: please use the parent repo [oracle-26ai-fsfo-tac-lab](https://github.com/krzysztof-i-cabaj/oracle-26ai-fsfo-tac-lab/issues) for now (or this folder's issues if the subproject is later extracted to its own repo).
