> [🇬🇧 English](./README.md) | 🇵🇱 Polski

# 📚 Legacy — Lessons Learned

> Archiwum knowledge base z **pierwszej iteracji środowiska** (`VMs/`), zachowane jako materiał edukacyjny.
> Produkcyjne wdrożenie LAB-a (druga iteracja, na której bazuje to repo) znajduje się w [`../../lab/`](../../lab/).

---

## Co tu jest?

### `FIXES_LOG.md`

**294 KB · 5 197 linii · 96 fixów (FIX-001 → FIX-096)**

Chronologiczny log napotkanych problemów i ich rozwiązań podczas pierwszej iteracji budowy laboratorium MAA Oracle 26ai (RAC + Active Data Guard + FSFO + TAC, 5 VM w VirtualBox).

Każdy wpis ma format:
- **Problem** — co poszło nie tak
- **Objaw** — co operator widział (komunikat, błąd, log)
- **Poprawka** — jak rozwiązane
- **Linki** do plików/sekcji których dotyczy

---

## Dlaczego "legacy"?

Pierwsza iteracja środowiska (`VMs/` w oryginalnym projekcie) była eksperymentalnym buildem — wiele decyzji konfiguracyjnych zostało zrewidowanych w drugiej iteracji (`VMs2-install/` → `lab/` w tym repo). Skrypty, kickstart i procedury w `lab/` są efektem przepisywania od zera na bazie wniosków z tych 96 fixów.

Sam `FIXES_LOG.md` zachowano, bo opisuje **kontrintuicyjne zjawiska Oracle**, które się nie zmieniły między 19c a 26ai i które prawdopodobnie pojawią się też u kogoś, kto będzie odtwarzał takie środowisko.

---

## Najciekawsze fix'y (krótki indeks)

| Fix | Temat | Dlaczego warto przeczytać |
|---|---|---|
| **FIX-004** | Kickstart backslash continuation | Anaconda nie wspiera `\` na końcu linii — typowy "tylko-jedna-instalacja" bug |
| **FIX-076** | FSFO Zero Data Loss = Flashback Database na **obu** | Auto-Reinstate wymaga Flashback po obu stronach broker config |
| **FIX-087** | Java 17+ TAC wymaga `--add-opens` | Proxy generation w UCP wymaga JVM module access dla `java.base/java.lang` |
| **FIX-090** | 26ai vs 19c SQL variants | Gdzie warto rozdzielić `*_19c.sql` od `*_26ai.sql` (CDB-aware checks) |
| **FIX-095** | Service TAC nie auto-startuje na non-Grid standby | Oracle Restart wymaga `srvctl modify pdb -policy AUTOMATIC -role PRIMARY` |

---

## Jak korzystać?

```bash
# Szybki przegląd struktury
grep -n "^## " FIXES_LOG.md | head -20

# Szukanie konkretnego problemu
grep -i -A 3 "ORA-XXXXX" FIXES_LOG.md

# Lista wszystkich 96 fix'ów
grep -E "^### FIX-[0-9]+" FIXES_LOG.md
```

---

**Status:** Archiwum read-only. Nowe lessons-learned z bieżących sesji trafiają do [`../../lab/EXECUTION_LOG_PL.md`](../../lab/EXECUTION_LOG_PL.md) (sesje S01–S28 = ~70 fix'ów S28-1..S28-68).
