# ⌨️ 02 — Boot Automation PoC (`VBoxManage keyboardputscancode`)

[![Sprint](https://img.shields.io/badge/Sprint-0-blue)]()
[![Status](https://img.shields.io/badge/Status-Implemented-success)]()
[![PoC](https://img.shields.io/badge/Type-Proof_of_Concept-orange)]()
[![Lang](https://img.shields.io/badge/PowerShell-5.1%2B-blue)]()
[![VBox](https://img.shields.io/badge/VirtualBox-7.x-darkgreen)]()
[![Layout](https://img.shields.io/badge/Keyboard-US-lightblue)]()

> 🎯 Sprint 0 — proof-of-concept. Cel: w pełni automatyczny boot kickstart bez ręcznej edycji GRUB.
> Goal: fully automated kickstart boot, no manual GRUB editing.

## 🎯 Kontekst / Context

[PL] We wszystkich istniejacych VM w LAB-ie `VMs2-install/` instalator wymaga recznej akcji uzytkownika
podczas bootu z ISO OL 8.10:
1. Na ekranie GRUB nacisnij **TAB** (lub **e**) zeby wejsc w edycje wpisu
2. Dopisz na koncu linii cmdline: `inst.ks=http://... inst.ip=...`
3. Nacisnij **Enter** (TAB) lub **Ctrl-X** (e) zeby zbootowac

Ten dokument opisuje mechanizm pelnej automatyzacji tego kroku przez VBoxManage.

[EN] This document describes how to fully automate kickstart boot via `VBoxManage keyboardputscancode`,
eliminating the manual GRUB edit step.

## ⚙️ Mechanizm / Mechanism

`VBoxManage controlvm <vm> keyboardputscancode <hex> [<hex>...]` wstrzykuje surowe scancode'y PC Set 1
bezposrednio do bufora klawiatury maszyny wirtualnej. Kazdy znak ASCII wymaga **pary**:

- **Make code** — naciśnięcie klawisza
- **Break code** — zwolnienie (= Make `OR` 0x80, ostatni bajt)

```
Klawisz 'e':       12  92          # make=0x12, break=0x92
Klawisz 'End':     e0 4f  e0 cf    # extended (e0 prefix), make=0x4f, break=0xcf
Klawisz Ctrl-X:    1d 2d  ad 9d    # Ctrl down, X down, X up, Ctrl up
```

Anaconda installer **czyta caly kernel cmdline** — nie tylko parametr `quiet` z domyslnego entry,
ale takze **dopisane** parametry typu `inst.ks=`, `inst.ip=`, `inst.text`. Wystarczy je dopisac
**na koncu linii** `linuxefi /images/pxeboot/vmlinuz ...`.

## 🎹 Sekwencja klawiszy / Keystroke sequence

| Krok | Klawisz | Cel [PL] | Goal [EN] |
|---|---|---|---|
| 0 | `Up` x 3 (default) | Wymus selekcje na pierwszej pozycji menu (Install) | Force first menu entry (Install) selection |
| 1 | `e` | Wejdz w edycje wybranego wpisu GRUB | Enter GRUB edit mode |
| 2 | `Down` x 2 (default) | Przejdz na linie `linuxefi` | Move to `linuxefi` line |
| 3 | `End` | Kursor na koniec tej linii | Cursor to end of line |
| 4 | Payload | Dopisz parametry kickstart | Append kickstart params |
| 5 | `Ctrl-X` | Boot z modyfikowana linia | Boot modified entry |

**Krok 0 dodany 2026-05-03 (iteracja 2):** GRUB-EFI moze pamietac poprzednia selekcje
przez `savedefault`. Bez `Up x 3` script wszedl w edit dla "Test this media & install"
zamiast "Install" — mediacheck dodal 3-5 min do procesu. `Up x 3` zapewnia powrot
do top entry niezaleznie od stanu poprzedniej sesji.

### Domyslny payload dla rcat01

```
 inst.ks=http://192.168.56.1:8000/ks-rcat01.cfg inst.ip=192.168.56.16::192.168.56.1:255.255.255.0::enp0s3:none inst.text
```

Spacja na poczatku jest celowa — oddziela payload od istniejacych parametrow w linii (jak `quiet`).

## 🏗️ Architektura skryptow / Script architecture

```
scripts/boot/
├── scancode_table.ps1          — PC Set 1 mapping (95 znakow ASCII + 25 klawiszy sterujacych)
├── send_vbox_keystrokes.ps1    — funkcja Send-VBoxKeystrokes z 3 trybami
├── start_kickstart_http.ps1    — Python http.server na 8000 (idempotentnie)
└── boot_rcat_via_scancode.ps1  — orchestrator: HTTP + startvm + sekwencja klawiszy + monitor
```

### scancode_table.ps1

Trzy hashtable:
- `$UnshiftedMakeCode` — 56 znakow podstawowych (litery male, cyfry, `=`, `-`, `.`, `/`, `:`...)
- `$ShiftedMakeCode` — 35 znakow shifted (litery wielkie, `!`, `@`, `_`...)
- `$ControlKeys` — 25 klawiszy sterujacych (strzalki, End, Enter, Ctrl, Shift...)

Plus helpery:
- `Get-CharScancodes -Char 'a'` → `@(0x1e, 0x9e)` (pare hex)
- `ConvertTo-Scancodes -Text "abc"` → flat array hex codes
- `Get-CtrlKeyScancodes -Char 'x'` → `@(0x1d, 0x2d, 0xad, 0x9d)` (Ctrl-X)

### send_vbox_keystrokes.ps1

Glowna funkcja `Send-VBoxKeystrokes` ma trzy tryby (PowerShell parameter sets):

```powershell
Send-VBoxKeystrokes -VM 'rcat01' -Text 'inst.text'              # tryb Text
Send-VBoxKeystrokes -VM 'rcat01' -ControlKey 'End'              # tryb Control
Send-VBoxKeystrokes -VM 'rcat01' -ControlKey 'Down' -RepeatControlKey 3
Send-VBoxKeystrokes -VM 'rcat01' -CtrlChord 'x'                 # tryb Ctrl
```

Batchowanie: kazda paczka max 80 par (160 bajtow), przerwa 50 ms miedzy paczkami.
Zapobiega przepełnieniu bufora klawiatury VBox (~256 zdarzen).

### boot_rcat_via_scancode.ps1

Orchestrator. Etapy:

1. **Pre-flight** — VM istnieje, nie jest running, kickstart present, Host-Only IF #2 z `192.168.56.1`
2. **HTTP server** — uruchamia (lub potwierdza) Python `http.server` na :8000
3. **Start VM** — `VBoxManage startvm <VM> --type {gui|headless}` (`gui` default dla debugowania)
4. **Wait** — `Start-Sleep $InitialDelaySec` (default 10s) na pojawienie sie GRUB-a
5. **Edit sequence** — 5 kroków klawiszy (zobacz tabela powyzej)
6. **Monitor** — `Test-NetConnection -ComputerName 192.168.56.16 -Port 22` co 15s, max 30 min

## ⚠️ Pulapki i jak je obsluzyc / Pitfalls and mitigation

### 1. Timing GRUB pojawia sie wolniej niz $InitialDelaySec

**Symptom:** `e` jest wyslany zanim GRUB sie pokazal — klawisz przepada,
po nadejsciu GRUB-a pierwszy znak `i` payloadu (z `inst.ks=`) wybiera entry "Install Oracle Linux"
i **ENTER nie potrzeba** — boot rusza ze starymi parametrami (bez kickstartu).

**Mitigation:**
- Zwieksz `-InitialDelaySec` do 15-20
- Lub wyslij `e` **kilka razy z odstepem** — pierwszy lapie GRUB, kolejne sa nieszkodliwe (powtarzaja edit toggle)

### 2. `Down` x 2 nie trafia w linie `linuxefi`

**Symptom:** Payload dopisuje sie do innej linii (np. `set gfxpayload=keep`),
GRUB nie ma argumentow w `linuxefi`, Anaconda startuje bez kickstartu.

**Mitigation:**
- Zwieksz `-DownArrowsCount` (default 2) do 3 lub 4
- Sprawdz konkretny grub.cfg z aktualnego ISO: `mount -o loop OracleLinux-R8-U10-x86_64-dvd.iso /mnt/iso`,
  potem `cat /mnt/iso/EFI/BOOT/grub.cfg`

### 3. Bufor klawiatury VBox sie przepełnia (~256 zdarzen)

**Symptom:** Czesc payloadu znika, GRUB kompiluje cmdline z dziurami.

**Mitigation:** Batchowanie w `Send-VBoxKeystrokes` (default 80 par/batch + 50ms przerwa) juz to obsluguje.
Jesli nadal problem — zmniejsz `-BatchSize` do 40 i zwieksz `-BatchDelayMs` do 100.

### 4. Uklad klawiatury — niemiecki/polski w VBox

**Symptom:** Znaki interpretowane jako QWERTZ/QWERTY-PL, payload bedzie niepoprawny
(np. `:` zostanie wstawiony jako `Ó`).

**Mitigation:** GRUB **zawsze** uzywa US layoutu niezaleznie od ustawien hosta — to jest decyzja
projektowa GRUB-a, nasz scancode_table.ps1 zaklada US i to jest poprawne.
**Nie zmieniaj** layoutu w skrypcie — bedzie gorzej.

### 5. Anaconda nie pobiera kickstart (HTTP 404)

**Symptom:** Anaconda startuje, ale rusza w trybie interaktywnym (TUI).

**Mitigation:**
- Sprawdz access log: `_RecoveryAppliance_/kickstart/.http_server.log.err`
  (UWAGA: Python http.server loguje GET requests do STDERR, nie STDOUT.
  Plik `.http_server.log` zwykle pusty — to TYLKO stdout.)
- Sprawdz reachability z VM: w trybie GUI po starcie Anaconda mozna otworzyc TTY (Ctrl-Alt-F2)
  i sprobowac `curl http://192.168.56.1:8000/ks-rcat01.cfg`
- Sprawdz Host-Only IF: `VBoxManage list hostonlyifs | Select-String 'IPAddress'`

## 🔀 Alternatywy do scancode injection (na przyszlosc)

### A. Repackowanie ISO

Wyciagnij ISO przez `xorriso`, podmień `EFI/BOOT/grub.cfg` na wersje z domyslnym entry zawierajacym
juz `inst.ks=...`, zapakuj z powrotem. Plus: deterministyczne, bez timingu. Minus: regeneracja ISO
przy zmianie URL kickstart, wymaga dodatkowych narzedzi (xorriso w PATH).

```bash
# Wyciag
xorriso -osirrox on -indev OL8.10-orig.iso -extract / iso_root/

# Modyfikacja
sed -i 's|linuxefi /images/pxeboot/vmlinuz|linuxefi /images/pxeboot/vmlinuz inst.ks=http://192.168.56.1:8000/ks-rcat01.cfg inst.ip=192.168.56.16::192.168.56.1:255.255.255.0::enp0s3:none inst.text|' iso_root/EFI/BOOT/grub.cfg

# Repack (bootable)
xorriso -as mkisofs -o OL8.10-rcat01.iso \
    -b isolinux/isolinux.bin -c isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot -e images/efiboot.img -no-emul-boot \
    -V 'OL-8-10-rcat' iso_root/
```

### B. OEMDRV (auto-detection)

Anaconda automatycznie wykrywa wirtualna dyskietke/USB z etykieta `OEMDRV` zawierajaca plik `ks.cfg`.
Plus: czyste, bez modyfikacji ISO. Minus: wymaga 1 mini-obrazu floppy/img per VM.

```powershell
# Stworz floppy z ks.cfg etykieta OEMDRV
$flpPath = "D:\VM\rcat01\oemdrv.img"
& dd if=/dev/zero of=$flpPath bs=1024 count=1440
& mkfs.fat -n OEMDRV $flpPath
& mount -o loop $flpPath /mnt/oemdrv
& cp ks-rcat01.cfg /mnt/oemdrv/ks.cfg
& umount /mnt/oemdrv

# Podpiete jako floppy do VM
VBoxManage storageattach rcat01 --storagectl Floppy --port 0 --device 0 --type fdd --medium $flpPath
```

### Kiedy wybrac ktora metode

| Metoda | Kiedy uzyc |
|---|---|
| **scancode** (Sprint 0) | Pojedyncza VM, szybki PoC, latwa zmiana parametrow per-VM |
| **ISO repack** | Wiele VM identycznej konfiguracji, deterministyczna powtarzalnosc |
| **OEMDRV** | Wiele VM ROZNEJ konfiguracji, czysta separacja per-VM |

## ✅ Walidacja Sprintu 0 / Sprint 0 validation

```powershell
# 1. Dry-run (sprawdz payload bez wykonania)
.\scripts\boot\boot_rcat_via_scancode.ps1 -DryRun

# 2. Test scancode_table osobno
. .\scripts\boot\scancode_table.ps1
ConvertTo-Scancodes -Text 'abc' | ForEach-Object { '{0:x2}' -f $_ }
# Oczekiwane: 1e 9e 30 b0 2e ae

# 3. Test Send-VBoxKeystrokes na zywym VM (innym niz rcat01, np. juz zainstalowanym)
. .\scripts\boot\send_vbox_keystrokes.ps1
Send-VBoxKeystrokes -VM 'infra01' -Text 'echo hello' -Verbose

# 4. Pelny boot (wymagana ks-rcat01.cfg + vbox_create_rcat.ps1 ze Sprint 1)
.\scripts\boot\boot_rcat_via_scancode.ps1
# Oczekiwane: po ~15-25 min SSH dostepny na 192.168.56.16:22; haslo z /root/.lab_secrets ($LAB_PASS, kickstart-managed)
```

## 📈 Skalowanie / Scaling

Jesli Sprint 0 zadziala dla rcat01, mechanizm bedzie mozna przeniesc do osobnego mini-projektu
**`VMs2-install/_KickstartAutomation_/`** dla wszystkich pozostalych 5 VM (`infra01`, `prim01/02`,
`stby01`, `client01`). Tabela parametrow per-VM:

| VM | IP | Plik kickstart | DownArrowsCount |
|---|---|---|---|
| infra01 | 192.168.56.10 | ks-infra01.cfg | 2 |
| prim01 | 192.168.56.11 | ks-prim01.cfg | 2 |
| prim02 | 192.168.56.12 | ks-prim02.cfg | 2 |
| stby01 | 192.168.56.13 | ks-stby01.cfg | 2 |
| client01 | 192.168.56.14 | ks-client01.cfg | 2 |
| **rcat01** | **192.168.56.16** | **ks-rcat01.cfg** | **2** |

To jest poza scope tego podprojektu — tutaj implementujemy tylko rcat01 jako PoC.

## 🔗 Referencje / References

- VirtualBox docs — VBoxManage controlvm: <https://www.virtualbox.org/manual/ch08.html#vboxmanage-controlvm>
- PC Set 1 scancode tables (USB HID): <https://wiki.osdev.org/PS/2_Keyboard>
- Anaconda kickstart docs: <https://anaconda-installer.readthedocs.io/en/latest/kickstart.html>
- GRUB EFI cmdline: linia `linuxefi /images/pxeboot/vmlinuz` przyjmuje wszystkie kernel parameters
