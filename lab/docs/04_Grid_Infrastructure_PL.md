> [🇬🇧 English](./04_Grid_Infrastructure.md) | 🇵🇱 Polski

# 04 — Instalacja Grid Infrastructure (VMs2-install)

> **Cel:** Zainstalowanie oprogramowania Oracle Grid Infrastructure 26ai (23.26.1). Wykonamy to w dwóch wariantach: na klastrze RAC (`prim01` i `prim02`) jako pełny Clusterware oraz na maszynie Standby (`stby01`) jako **Oracle Restart** (Standalone Server) do zarządzania usługami.

Dokument opisuje dwie metody wdrożenia: zautomatyzowaną (skryptową) oraz w pełni manualną krok po kroku.

---

## 1. Wymagania wstępne (Prereq)

1.  Współdzielone dyski zmapowane na `prim01` i `prim02` jako `/dev/oracleasm/OCR*`, `DATA1`, `RECO1` (krok 03_Storage).
2.  Zbudowane relacje bezhasłowe (SSH) dla użytkowników `oracle` i `grid` między maszynami (krok 02_Przygotowanie).
3.  Zainstalowany i uruchomiony DNS na maszynie `infra01` poprawnie rozwiązujący nazwę klastra SCAN (`scan-prim.lab.local`).
4.  Skonfigurowane profile środowiskowe (`ORACLE_HOME`, `PATH`) dla użytkowników `grid` i `oracle` na wszystkich węzłach — wykonaj **raz** jako root na `prim01`:
    ```bash
    sudo bash /tmp/scripts/setup_oracle_env.sh
    ```
    Skrypt ustawia `.bash_profile` na `prim01`, `prim02` i `stby01` oraz naprawia właściwość `/etc/oraInst.loc` (wymagane przez CVU). Idempotentny — bezpieczny do ponownego uruchomienia.

### Pliki instalacyjne z hosta (Windows)
W plikach `.cfg` (kickstart) został uwzględniony punkt montowania `/mnt/oracle_binaries`. Pakiety te powinny zawierać ZIP instalatora 23.26 Grid (`V1054596-01...zip`).

---

## Metoda 1: Szybka Ścieżka Automatyczna (Zalecana)

Skrypt `install_grid_silent.sh` automatyzuje dekompresję (Image Install) oraz wywołanie instalatora z odpowiednimi flagami pomijania ostrzeżeń.

### 2. Instalacja Grid Infrastructure dla 2-node RAC (prim01, prim02)

1.  Zaloguj się na `prim01` jako użytkownik `grid`:
    ```bash
    su - grid
    bash /tmp/scripts/install_grid_silent.sh /tmp/response_files/grid_rac.rsp
    ```

2.  Gdy installer zakończy fazę software i wyświetli komunikat:
    ```
    Successfully Setup Software.
    As install user, run the following command to complete the configuration.
            /u01/app/23.26/grid/gridSetup.sh -executeConfigTools ...
    ```
    **Nie uruchamiaj jeszcze executeConfigTools** — najpierw root scripts. Otwórz nowy terminal na `prim01` jako `root`:
    ```bash
    /u01/app/oraInventory/orainstRoot.sh
    /u01/app/23.26/grid/root.sh
    ```
    **Poczekaj na zakończenie root.sh na prim01 przed przejściem dalej (5–15 min).**

3.  Następnie na węźle `prim02` jako `root` (dopiero po zakończeniu prim01!):
    ```bash
    /u01/app/23.26/grid/root.sh
    ```
    **Poczekaj na zakończenie.**

4.  Wróć na `prim01` jako `grid` i uruchom konfigurację narzędzi (executeConfigTools):
    ```bash
    export CV_ASSUME_DISTID=OEL8.10
    /u01/app/23.26/grid/gridSetup.sh -executeConfigTools \
        -responseFile /tmp/response_files/grid_rac.rsp -silent
    ```

### 2a. Tworzenie diskgroup +DATA i +RECO

`grid_rac.rsp` tworzy tylko `+OCR`. Przed instalacją bazy (krok 05) utwórz `+DATA` i `+RECO` — DBCA zakłada ich istnienie.

Jako **`grid@prim01`**:

```bash
# +DATA (EXTERNAL redundancy — 1 dysk)
asmca -silent -createDiskGroup \
    -diskGroupName DATA \
    -diskList /dev/oracleasm/DATA1 \
    -redundancy EXTERNAL \
    -au_size 4 \
    -sysAsmPassword 'Oracle26ai_LAB!'

# +RECO (EXTERNAL redundancy — 1 dysk)
asmca -silent -createDiskGroup \
    -diskGroupName RECO \
    -diskList /dev/oracleasm/RECO1 \
    -redundancy EXTERNAL \
    -au_size 4 \
    -sysAsmPassword 'Oracle26ai_LAB!'

# Weryfikacja — oczekiwane: OCR (NORMAL) + DATA (EXTERN) + RECO (EXTERN), wszystkie MOUNTED
asmcmd lsdg
```

### 3. Instalacja Oracle Restart na stby01 (Standalone)

> `grid_restart.rsp` używa `installOption=CRS_SWONLY` — instaluje binari bez walidacji storage. Oracle GI 23.26.1 ignoruje `FILE_SYSTEM_STORAGE` w trybie `HA_CONFIG` (zawsze wymaga dysków ASM — INS-30507), dlatego używamy `CRS_SWONLY`. Po `root.sh` (bazowe OS setup) konfigurację OHAS wykonuje `roothas.pl`.

1.  Zaloguj się na `stby01` jako użytkownik `grid`:
    ```bash
    su - grid
    bash /tmp/scripts/install_grid_silent.sh /tmp/response_files/grid_restart.rsp
    ```

2.  Po komunikacie "Successfully Setup Software", na `stby01` jako `root`:
    ```bash
    /u01/app/23.26/grid/root.sh
    ```
    `root.sh` dla `CRS_SWONLY` wykonuje tylko bazowe OS setup (oraenv, oratab) — **nie konfiguruje OHAS**.

3.  Konfiguracja Oracle Restart (OHAS) — jako `root` na `stby01`:
    ```bash
    /u01/app/23.26/grid/perl/bin/perl \
        -I /u01/app/23.26/grid/perl/lib \
        -I /u01/app/23.26/grid/crs/install \
        /u01/app/23.26/grid/crs/install/roothas.pl
    ```
    Oczekiwany komunikat: `CLSRSC-327: Successfully configured Oracle Restart for a standalone server`

Przejdź do sekcji **4. Weryfikacja Instalacji**.

---

## Metoda 2: Ścieżka Manualna (Krok po kroku)

Dla instalacji manualnej wykonujemy proces z wyodrębnieniem komend dla Image Install. Pamiętaj by ustawić zmienne systemowe omijające weryfikatory OS.

### 2. Instalacja Grid Infrastructure dla 2-node RAC (prim01, prim02)

Zaloguj się na `prim01` jako użytkownik `grid`.

```bash
# Ustawienie zmiennej oszukującej weryfikator dystrybucji
export CV_ASSUME_DISTID=OEL8.10
export GRID_HOME=/u01/app/23.26/grid

# Dekompresja pliku instalacyjnego z użyciem trybu Image Install
mkdir -p $GRID_HOME
cd $GRID_HOME
unzip -q /mnt/oracle_binaries/V1054596-01-OracleDatabase23.26.1.0.0forLinux_x86-64.zip

# Instalacja cicha w klastrze wykorzystująca wcześniej przygotowany RSP
./gridSetup.sh -silent -ignorePrereqFailure -responseFile /tmp/response_files/grid_rac.rsp
```

Gdy instalator zwróci komunikat o wykonaniu skryptów ROOT:
Zaloguj się na **`prim01`** jako `root`:
```bash
/u01/app/23.26/grid/root.sh
```
Poczekaj na zakończenie sukcesem (utworzenie lokalnego ASM OCR). Następnie zaloguj się na **`prim02`** jako `root`:
```bash
/u01/app/23.26/grid/root.sh
```

Wróć na konto `grid` na `prim01` i wywołaj skrypt zakańczający instalację, by zaktualizować Oracle Inventory.
```bash
/u01/app/23.26/grid/gridSetup.sh -executeConfigTools -responseFile /tmp/response_files/grid_rac.rsp -silent
```

### 2a. Tworzenie diskgroup +DATA i +RECO

```bash
asmca -silent -createDiskGroup \
    -diskGroupName DATA \
    -diskList /dev/oracleasm/DATA1 \
    -redundancy EXTERNAL \
    -au_size 4 \
    -sysAsmPassword 'Oracle26ai_LAB!'

asmca -silent -createDiskGroup \
    -diskGroupName RECO \
    -diskList /dev/oracleasm/RECO1 \
    -redundancy EXTERNAL \
    -au_size 4 \
    -sysAsmPassword 'Oracle26ai_LAB!'

asmcmd lsdg
```

### 3. Instalacja Oracle Restart na stby01 (Standalone)

> `grid_restart.rsp` używa `installOption=CRS_SWONLY` — brak walidacji storage. `root.sh` dla `CRS_SWONLY` wykonuje tylko bazowe OS setup — OHAS konfiguruje `roothas.pl`.

Zaloguj się na `stby01` jako użytkownik `grid`.

```bash
export CV_ASSUME_DISTID=OEL8.10
export GRID_HOME=/u01/app/23.26/grid

mkdir -p $GRID_HOME
cd $GRID_HOME
unzip -q /mnt/oracle_binaries/V1054596-01-OracleDatabase23.26.1.0.0forLinux_x86-64.zip

./gridSetup.sh -silent -ignorePrereqFailure -responseFile /tmp/response_files/grid_restart.rsp
```

Po komunikacie "Successfully Setup Software", jako `root` na **`stby01`**:
```bash
/u01/app/23.26/grid/root.sh

# Konfiguracja Oracle Restart (OHAS) — root.sh dla CRS_SWONLY nie konfiguruje OHAS:
/u01/app/23.26/grid/perl/bin/perl \
    -I /u01/app/23.26/grid/perl/lib \
    -I /u01/app/23.26/grid/crs/install \
    /u01/app/23.26/grid/crs/install/roothas.pl
# Oczekiwane: CLSRSC-327: Successfully configured Oracle Restart for a standalone server
```

---

## 4. Weryfikacja Instalacji

> **Jeśli `crsctl: command not found`** — profil użytkownika `grid` nie ma ustawionego `ORACLE_HOME`. Ustaw go raz (lub sprawdź sekcję 2.14 w `02b_OS_Preparation_Manual_PL.md`):
> ```bash
> export ORACLE_HOME=/u01/app/23.26/grid
> export PATH=$ORACLE_HOME/bin:$PATH
> ```
>
> **Jeśli `sqlplus / as sysasm` zwraca ORA-12162** — brakuje `ORACLE_SID`. Ustaw przed wywołaniem sqlplus:
> ```bash
> export ORACLE_SID=+ASM1   # prim01; na prim02: +ASM2; na stby01: +ASM
> ```

Weryfikacja statusu klastra RAC (na **`prim01`** jako `grid`):
```bash
crsctl stat res -t
```
Powinieneś zobaczyć uruchomione usługi oraz podłączone grupy dyskowe (`ora.OCR.dg`).

Weryfikacja statusu Oracle Restart (na **`stby01`** jako `grid`):
```bash
crsctl check has
# Oczekiwany output: CRS-4638: Oracle High Availability Services is online
```

Dzięki temu środowisko główne działa w oparciu o High Availability Klastra RAC, a środowisko na Standby będzie w stanie automatycznie i niezawodnie zarządzać działaniem lokalnej instancji bazy i jej siecią.

---
**Następny krok:** `05_Database_Primary.md`

