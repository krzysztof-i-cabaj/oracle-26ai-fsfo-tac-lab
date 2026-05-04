# ==============================================================================
# Tytul:        boot_rcat_via_scancode.ps1
# Opis:         Orkiestrator Sprintu 0 - w pelni automatyczny boot rcat01 z ISO
#               OL 8.10 + kickstart, bez interakcji uzytkownika.
#               Sekwencja:
#                 1. start HTTP server (start_kickstart_http.ps1)
#                 2. VBoxManage startvm rcat01
#                 3. wait na GRUB (--initialDelaySec)
#                 4. 'e' (edit entry)
#                 5. 'Down' x N (na linie linuxefi)
#                 6. 'End' (kursor na koniec linii)
#                 7. payload: ' inst.ks=... inst.ip=... inst.text'
#                 8. 'Ctrl-X' (boot)
#                 9. monitor VM az do poweroff (Anaconda autoreboot po install)
#                10. (opcjonalnie) wait SSH na 192.168.56.16:22
# Description [EN]: Sprint 0 orchestrator - fully automated kickstart boot of rcat01.
#
# Autor:        KCB Kris
# Data:         2026-05-01
# Wersja:       1.0
# <repo>:       ZDLRA_like
# Konwencje:    ZDLRA_like/SETTINGS.md
#
# Wymagania [PL]:    - VM rcat01 utworzona przez vbox_create_rcat.ps1 (Sprint 1)
#                    - VM w stanie 'powered off' (lub 'aborted')
#                    - Plik kickstart/ks-rcat01.cfg dostepny do podania przez HTTP
#                    - Port 8000 wolny lub serwer juz nasz
# Requirements [EN]: - VM created (Sprint 1), powered off, ks file present, port 8000 OK
#
# Uzycie [PL]:  .\boot_rcat_via_scancode.ps1                    # default GUI mode
#               .\boot_rcat_via_scancode.ps1 -Headless           # bez GUI
#               .\boot_rcat_via_scancode.ps1 -DryRun             # wypisz tylko, nie wysylaj
#               .\boot_rcat_via_scancode.ps1 -DownArrowsCount 3  # jesli default 2 nie trafia w linuxefi
# Usage [EN]:   Default = GUI for debugging. -Headless | -DryRun | -DownArrowsCount.
# ==============================================================================

[CmdletBinding()]
param(
    [string]$VM = "rcat01",
    [string]$IP = "192.168.56.16",
    [string]$Gateway = "192.168.56.1",
    [string]$Netmask = "255.255.255.0",
    [int]$HttpPort = 8000,
    [string]$KickstartFilename = "ks-rcat01.cfg",
    [int]$InitialDelaySec = 25,                # EFI-GRUB needs more time than BIOS-isolinux (was 10, bumped 2026-05-03)
    [int]$UpArrowsBeforeEdit = 3,              # Force selection to first menu entry (Install) before 'e' (added 2026-05-03)
    [int]$DownArrowsCount = 2,
    [int]$PostEditDelayMs = 500,
    [switch]$Headless,
    [switch]$DryRun,
    [switch]$SkipHttpStart,
    [int]$PostBootMonitorTimeoutSec = 1800
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Imports
# ---------------------------------------------------------------------------
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot 'send_vbox_keystrokes.ps1')

$VBoxManage = $script:VBoxManagePath  # ustawiony przez send_vbox_keystrokes.ps1

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
Write-Host "========== PRE-FLIGHT CHECKS ==========" -ForegroundColor Cyan

# 1) VM istnieje?
$vmList = & $VBoxManage list vms
if (-not ($vmList | Select-String "`"$VM`"")) {
    throw "VM '$VM' nie istnieje. Najpierw uruchom .\scripts\vbox_create_rcat.ps1 (Sprint 1)."
}
Write-Host "  [OK] VM '$VM' istnieje."

# 2) VM nie jest running?
$info = & $VBoxManage showvminfo $VM --machinereadable
$stateLine = $info | Where-Object { $_ -match '^VMState=' }
if ($stateLine -match '"running"') {
    throw "VM '$VM' juz dziala. Najpierw zatrzymaj: VBoxManage controlvm $VM poweroff"
}
Write-Host "  [OK] VM '$VM' jest w stanie: $stateLine"

# 3) Plik kickstart istnieje?
$kickstartDir = Join-Path (Split-Path -Parent (Split-Path -Parent $scriptRoot)) 'kickstart'
$kickstartFile = Join-Path $kickstartDir $KickstartFilename
if (-not (Test-Path $kickstartFile)) {
    throw "Plik kickstart nie istnieje: $kickstartFile (Sprint 1: utworz ks-rcat01.cfg)"
}
Write-Host "  [OK] Kickstart: $kickstartFile"

# 4) Hostonly IF ma 192.168.56.1?
# Match po IP (nie po InterfaceAlias) - Windows skraca alias do 'Ethernet N',
# nie pasuje do 'VirtualBox Host-Only Ethernet Adapter #2' (false-positive WARN
# w iteracji 1 z 2026-05-03). IP jest source-of-truth, nie nazwa adaptera.
$hoIp = (Get-NetIPAddress -IPAddress $Gateway -ErrorAction SilentlyContinue).IPAddress
if (-not $hoIp) {
    Write-Host "  [WARN] Brak interfejsu z IP '$Gateway' na hoscie. Kickstart moze nie zostac pobrany." -ForegroundColor Yellow
    Write-Host "         Sprawdz: VBoxManage list hostonlyifs | Select-String 'IPAddress'" -ForegroundColor Yellow
} else {
    $hoAlias = (Get-NetIPAddress -IPAddress $Gateway -ErrorAction SilentlyContinue).InterfaceAlias
    Write-Host "  [OK] Host-Only IF ma $Gateway (interface: $hoAlias)."
}

# ---------------------------------------------------------------------------
# Build payload
# ---------------------------------------------------------------------------
$ksUrl   = "http://${Gateway}:${HttpPort}/${KickstartFilename}"
$payload = " inst.ks=$ksUrl inst.ip=${IP}::${Gateway}:${Netmask}::enp0s3:none inst.text"

Write-Host ""
Write-Host "========== PAYLOAD ==========" -ForegroundColor Cyan
Write-Host "Kickstart URL: $ksUrl"
Write-Host "Cmdline payload (do dopisania na koncu linii linuxefi):"
Write-Host "  $payload" -ForegroundColor White
Write-Host "Sekwencja klawiszy:"
Write-Host "  Up x $UpArrowsBeforeEdit  ->  e  ->  Down x $DownArrowsCount  ->  End  ->  '<payload>'  ->  Ctrl-X"

if ($DryRun) {
    Write-Host ""
    Write-Host "[DRY-RUN] Koncze bez wysylania klawiszy ani uruchamiania VM." -ForegroundColor Yellow
    return
}

# ---------------------------------------------------------------------------
# Start HTTP server
# ---------------------------------------------------------------------------
if (-not $SkipHttpStart) {
    Write-Host ""
    Write-Host "========== HTTP SERVER ==========" -ForegroundColor Cyan
    & (Join-Path $scriptRoot 'start_kickstart_http.ps1') -Port $HttpPort
}

# ---------------------------------------------------------------------------
# Start VM
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "========== START VM ==========" -ForegroundColor Cyan
$bootType = if ($Headless) { 'headless' } else { 'gui' }
Write-Host "Mode: $bootType"
& $VBoxManage startvm $VM --type $bootType
if ($LASTEXITCODE -ne 0) { throw "VBoxManage startvm $VM zakonczyl sie bledem." }

Write-Host "Czekam $InitialDelaySec s na pojawienie sie GRUB-a..."
Start-Sleep -Seconds $InitialDelaySec

# Sanity: VM nadal running (a nie autoboot wystartowal sam)
$info = & $VBoxManage showvminfo $VM --machinereadable
$stateLine = $info | Where-Object { $_ -match '^VMState=' }
if (-not ($stateLine -match '"running"')) {
    throw "VM po startvm nie jest 'running' (jest: $stateLine). Cos nie tak."
}

# ---------------------------------------------------------------------------
# Wyslij sekwencje klawiszy
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "========== EDIT GRUB ENTRY ==========" -ForegroundColor Cyan

# 0) Up x N - wymus selekcje na PIERWSZEJ pozycji menu (Install).
# Powod: GRUB EFI moze pamietac poprzednia selekcje przez savedefault.
# W iteracji 2 (2026-05-03) Test entry zostal wybrany przez przypadek -> mediacheck.
# 0) Up x N - force selection to FIRST menu entry (Install). GRUB-EFI may remember
# previous selection via savedefault. Iteration 2 hit Test entry by accident.
if ($UpArrowsBeforeEdit -gt 0) {
    Write-Host "  [0/6] Wysylam 'Up' x $UpArrowsBeforeEdit (zapewnij default = pierwsza pozycja menu)..."
    Send-VBoxKeystrokes -VM $VM -ControlKey 'Up' -RepeatControlKey $UpArrowsBeforeEdit
    Start-Sleep -Milliseconds 200
}

# 1) 'e' - enter edit mode
Write-Host "  [1/6] Wysylam 'e' (edit GRUB entry)..."
Send-VBoxKeystrokes -VM $VM -Text 'e'
Start-Sleep -Milliseconds $PostEditDelayMs

# 2) Down x N - przejdz na linie linuxefi
Write-Host "  [2/6] Wysylam 'Down' x $DownArrowsCount..."
Send-VBoxKeystrokes -VM $VM -ControlKey 'Down' -RepeatControlKey $DownArrowsCount
Start-Sleep -Milliseconds 200

# 3) End - kursor na koniec linii
Write-Host "  [3/6] Wysylam 'End' (kursor na koniec linii)..."
Send-VBoxKeystrokes -VM $VM -ControlKey 'End'
Start-Sleep -Milliseconds 200

# 4) Payload
Write-Host "  [4/6] Wysylam payload ($($payload.Length) znakow, batchami)..."
Send-VBoxKeystrokes -VM $VM -Text $payload
Start-Sleep -Milliseconds $PostEditDelayMs

# 5) Ctrl-X - boot
Write-Host "  [5/6] Wysylam Ctrl-X (boot z modyfikowana linia)..."
Send-VBoxKeystrokes -VM $VM -CtrlChord 'x'

Write-Host ""
Write-Host "[OK] Sekwencja wyslana. Anaconda powinna pobrac kickstart i rozpoczac instalacje." -ForegroundColor Green
Write-Host "Postep instalacji: VirtualBox GUI / VBoxManage controlvm $VM screenshotpng <plik>" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Monitor: czekaj az VM zostanie wylaczona (Anaconda autoreboot konczy z poweroff
# jesli kickstart ma 'reboot --eject' albo 'shutdown'; OL 8.10 default to 'reboot').
# Anaconda 'reboot' restartuje VM, wiec stan zostanie running. Tu mozemy poczekac
# na drugi cykl 'running' gdzie VM bootuje z dysku (juz bez ISO).
# Prosciej: czekamy az pojawi sie SSH na 192.168.56.16:22.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "========== MONITOR INSTALL ==========" -ForegroundColor Cyan
Write-Host "Czekam az SSH bedzie dostepny na ${IP}:22 (max $PostBootMonitorTimeoutSec s)..."

$deadline = (Get-Date).AddSeconds($PostBootMonitorTimeoutSec)
$sshUp = $false
while ((Get-Date) -lt $deadline) {
    $test = Test-NetConnection -ComputerName $IP -Port 22 -InformationLevel Quiet -WarningAction SilentlyContinue
    if ($test) { $sshUp = $true; break }
    Start-Sleep -Seconds 15
    $remaining = [int]($deadline - (Get-Date)).TotalSeconds
    Write-Host "  ... czekam ($remaining s pozostalo)"
}

if ($sshUp) {
    Write-Host ""
    Write-Host "[SUCCESS] rcat01 zainstalowany i SSH dostepny na ${IP}:22." -ForegroundColor Green
    Write-Host "Kolejne kroki (Sprint 1):"
    Write-Host "  ssh kris@$IP   # haslo z /root/.lab_secrets (LAB_PASS, kickstart utworzyl chmod 600)"
    Write-Host "  scp scripts/install_db_silent_rcat.sh  kris@${IP}:/tmp/"
} else {
    Write-Host ""
    Write-Host "[TIMEOUT] SSH na ${IP}:22 nie odpowiada po $PostBootMonitorTimeoutSec s." -ForegroundColor Red
    Write-Host "Sprawdz w VirtualBox GUI co sie dzieje. Mozliwe przyczyny:" -ForegroundColor Yellow
    Write-Host "  - GRUB nie zlapal payloadu (zwieksz -DownArrowsCount lub -InitialDelaySec)"
    Write-Host "  - Anaconda blad (zobacz konsole w GUI lub /tmp/anaconda.log)"
    Write-Host "  - Sieci nie wstaly (sprawdz inst.ip= w payload)"
    exit 1
}
