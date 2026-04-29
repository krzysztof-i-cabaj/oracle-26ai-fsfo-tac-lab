> [🇬🇧 English](./05_Database_Primary.md) | 🇵🇱 Polski

# 05 — Instalacja Bazy Danych i Tworzenie Primary (VMs2-install)

> **Cel:** Instalacja oprogramowania Oracle Database 26ai (23.26.1) w trybie *Software Only* na klastrze RAC (`prim01`, `prim02`) oraz utworzenie na nim Głównej Bazy Danych (Primary CDB: `PRIM`) z jedną podłączaną bazą PDB (`APPPDB`).
> **Zależności:** Poprawnie działający Grid Infrastructure i uruchomione dyski ASM (`+OCR`, `+DATA`, `+RECO`).

Dokument opisuje dwie metody wdrożenia: zautomatyzowaną (skryptową) oraz w pełni manualną krok po kroku.

---

## Metoda 1: Szybka Ścieżka Automatyczna (Zalecana)

Wszystkie kroki zostały zaszyte w dwóch skryptach. Zaloguj się na **`prim01`** jako użytkownik **`oracle`**:

```bash
# 1. Instalacja oprogramowania Bazy Danych
bash /tmp/scripts/install_db_silent.sh /tmp/response_files/db.rsp

# Po zakończeniu zaloguj się jako ROOT na prim01 i prim02 i wykonaj:
# /u01/app/oracle/product/23.26/dbhome_1/root.sh
```

```bash
# 2. Tworzenie Głównej Bazy Danych (CDB/PDB)
su - oracle

# Proces potrwa ok. 30-50 minut — uruchom w nohup aby sesja SSH/MobaXterm
# nie przerywała DBCA po rozłączeniu.
nohup bash /tmp/scripts/create_primary.sh /tmp/response_files/dbca_prim.rsp \
    > /tmp/create_primary_$(date +%Y%m%d_%H%M).log 2>&1 &
echo "PID: $!"

# Podgląd postępu w tej samej lub nowej sesji:
tail -f /u01/app/oracle/cfgtoollogs/dbca/PRIM/PRIM.log
```

> **Uwaga:** Dla długich procesów (DBCA, RMAN DUPLICATE, Data Guard sync) zawsze używaj `nohup ... &` lub `screen`/`tmux`. Zerwaną sesję SSH MobaXterm kończy proces razem z DBCA, co wymaga czyszczenia częściowo utworzonej bazy (`dbca -deleteDatabase`) przed ponowną próbą.

Skrypt nr 2 na koniec automatycznie przełącza bazę w tryb `MOUNT` i włącza krytyczne funkcje: `ARCHIVELOG`, `FORCE LOGGING` oraz `FLASHBACK ON`. Jeśli użyłeś tej metody, możesz przejść od razu do sekcji **Weryfikacja**.

---

## Metoda 2: Ścieżka Manualna (Krok po kroku)

Jeśli wolisz mieć pełną kontrolę i zrozumieć każdy etap, postępuj zgodnie z poniższymi instrukcjami. Zaloguj się na **`prim01`** jako użytkownik **`oracle`**.

### Krok 1: Wypakowanie plików binarnych do ORACLE_HOME

```bash
export DB_HOME="/u01/app/oracle/product/23.26/dbhome_1"
export DB_ZIP="/mnt/oracle_binaries/V1054592-01-OracleDatabase23.26.1.0.0forLinux_x86-64.zip"

cd $DB_HOME
unzip -q $DB_ZIP
```

### Krok 2: Cicha Instalacja (Software-Only)

```bash
export CV_ASSUME_DISTID=OEL8.10

$DB_HOME/runInstaller -silent -ignorePrereqFailure -responseFile /tmp/response_files/db.rsp
```

Po pomyślnym wykonaniu się instalatora, w konsoli otrzymasz prośbę o uruchomienie skryptów root. Wykonaj poniższe polecenie jako użytkownik **`root`** najpierw na **`prim01`**, a potem na **`prim02`**:

```bash
# Jako root
/u01/app/oracle/product/23.26/dbhome_1/root.sh
```

### Krok 3: Tworzenie Bazy Danych w DBCA

Wykorzystamy DBCA z wymuszonym szablonem `New_Database.dbt` (dzięki temu baza kreuje się poprawnie w architekturze 26ai bez błędów "Seed").

```bash
# Jako oracle na prim01
$DB_HOME/bin/dbca -silent -createDatabase -responseFile /tmp/response_files/dbca_prim.rsp
```

Operacja ta potrwa od 30 do 50 minut w zależności od wydajności Storage LVM.

### Krok 4: Włączenie ARCHIVELOG, FORCE LOGGING i FLASHBACK

Świeżo utworzona przez DBCA baza startuje standardowo w trybie `NOARCHIVELOG`. Do skonfigurowania usługi Data Guard logowanie zmian oraz technologia Flashback są niezbędne.

```bash
# Jako oracle na prim01
export ORACLE_SID=PRIM1
export ORACLE_HOME=/u01/app/oracle/product/23.26/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH

# Zatrzymanie klastrowej bazy i uruchomienie w trybie MOUNT
srvctl stop database -d PRIM
srvctl start database -d PRIM -startoption mount
```

Zmień parametry wewnątrz bazy:
```bash
sqlplus / as sysdba
```
```sql
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE FORCE LOGGING;
ALTER DATABASE FLASHBACK ON;
ALTER DATABASE OPEN;
EXIT;
```

---

## 3. Logi DBCA — gdzie szukać w razie problemów

Skrypt wypisuje postęp DBCA na stdout. Jeśli coś pójdzie nie tak, szczegóły znajdziesz w:

| Log | Zawartość |
|-----|-----------|
| `/u01/app/oracle/cfgtoollogs/dbca/PRIM/PRIM.log` | **Główny log DBCA** — tu szukaj błędów w pierwszej kolejności |
| `/u01/app/oraInventory/logs/dbca*.log` | Logi prereq i inventory |
| `/u01/app/oracle/diag/rdbms/prim/PRIM1/trace/alert_PRIM1.log` | Alert log instancji (błędy po starcie) |

Aby śledzić postęp na bieżąco i zachować pełny log w jednym pliku:
```bash
bash /tmp/scripts/create_primary.sh /tmp/response_files/dbca_prim.rsp \
    2>&1 | tee /tmp/create_primary_$(date +%Y%m%d_%H%M).log
```

Podgląd głównego logu DBCA w trakcie działania (w osobnym terminalu):
```bash
tail -f /u01/app/oracle/cfgtoollogs/dbca/PRIM/PRIM.log
```

---

## 5. Weryfikacja

Upewnij się, że usługa bazy działa na obu węzłach klastra, a jej status na serwerze to "Open".

```bash
# Jako oracle na prim01
srvctl status database -d PRIM
# Oczekiwany wynik: Instance PRIM1 is running on node prim01, Instance PRIM2 is running on node prim02

sqlplus / as sysdba
```
```sql
SELECT log_mode, flashback_on, force_logging FROM v$database;
```
Wyniki zapytania muszą wskazywać: `ARCHIVELOG`, `YES` (dla Flashback) i `YES` (dla Force Logging).

Jeśli baza spełnia te warunki, jest w 100% gotowa na wykonanie konfiguracji środowiska typu Standby.

---
**Następny krok:** `06_Data_Guard_Standby.md`

